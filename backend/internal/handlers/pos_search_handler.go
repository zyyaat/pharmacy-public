package handlers

import (
        "log"
        "net/http"
        "sort"
        "strings"
        "sync"
        "time"

        "github.com/gin-gonic/gin"
)

// POS smart search — typo-tolerant, scanner-tolerant product lookup.
//
// Two-tier architecture (why it stays fast under load):
//
//      Tier 1 — ONE indexed SQL statement: barcode equality/prefix on the unique
//      btree, name prefix/substring + trigram similarity on the GIN trigram
//      indexes from migration 17. This catches كاربيمازون (1-char typo) and all
//      barcode misreads that keep most characters.
//
//      Tier 2 — Go-side levenshtein over the pharmacy's own product names, used
//      ONLY when tier 1 returned fewer results than the limit. The id/name list
//      is bounded by the pharmacy's catalog (not the global catalog), cached
//      in-process for 30s, and costs microseconds per row. This catches heavy
//      garbling (كاربيمازول → كانبيبالول) that no index can answer. Matched IDs
//      are then re-fetched with authoritative prices and live stock in one
//      indexed query — cache never serves money or stock data.
//
//      Tier 2 freshness tradeoff: products created/renamed in the last 30s
//      appear in exact/prefix search immediately (tier 1) and in fuzzy results
//      within 30s at most.

const (
        posSearchDefaultLimit = 8
        posSearchMaxLimit     = 10
        posSearchMinQueryLen  = 2
        posSearchMaxQueryLen  = 100
        // Trigram similarity floor: loose enough to catch 2-3 character typos in
        // Arabic drug names (كاربيمازول → كانبيبالول), strict enough to keep the
        // matched subset small on large catalogs.
        posFuzzyThreshold = 0.24
)

// escapeLike neutralizes LIKE wildcards so user input can never widen the
// pattern (e.g. "%%%") or bypass the trigram index usage.
func escapeLike(value string) string {
        return strings.NewReplacer(`\`, `\\`, `%`, `\%`, `_`, `\_`).Replace(value)
}

// ---------------------------------------------------------------------------
// Tier 2 — in-process fuzzy catalog (levenshtein), cached per pharmacy.
// ---------------------------------------------------------------------------

const (
        fuzzyCatalogTTL       = 30 * time.Second
        fuzzyMinNameRunes     = 5  // shorter names are handled by prefix/trigram tiers
        fuzzyMinQueryRunes    = 5  // garbling only makes sense on meaningful words
)

type fuzzyCatalogEntry struct {
        id    string
        name  string
        gname string
}

type fuzzyCatalog struct {
        entries  []fuzzyCatalogEntry
        loadedAt time.Time
}

var fuzzyCatalogCache sync.Map // pharmacyID -> *fuzzyCatalog

func getCachedFuzzyCatalog(pharmacyID string, load func() ([]fuzzyCatalogEntry, error)) ([]fuzzyCatalogEntry, error) {
        if cached, ok := fuzzyCatalogCache.Load(pharmacyID); ok {
                cat := cached.(*fuzzyCatalog)
                if time.Since(cat.loadedAt) < fuzzyCatalogTTL {
                        return cat.entries, nil
                }
        }
        entries, err := load()
        if err != nil {
                return nil, err
        }
        fuzzyCatalogCache.Store(pharmacyID, &fuzzyCatalog{entries: entries, loadedAt: time.Now()})
        return entries, nil
}

// levenshtein computes edit distance over runes (Arabic-safe) with the
// classic two-row DP — O(len(a)*len(b)) time, O(min) space.
func levenshtein(a, b []rune) int {
        if len(a) == 0 {
                return len(b)
        }
        if len(b) == 0 {
                return len(a)
        }
        prev := make([]int, len(b)+1)
        curr := make([]int, len(b)+1)
        for j := 0; j <= len(b); j++ {
                prev[j] = j
        }
        for i := 1; i <= len(a); i++ {
                curr[0] = i
                for j := 1; j <= len(b); j++ {
                        cost := 1
                        if a[i-1] == b[j-1] {
                                cost = 0
                        }
                        curr[j] = min3(curr[j-1]+1, prev[j]+1, prev[j-1]+cost)
                }
                prev, curr = curr, prev
        }
        return prev[len(b)]
}

func min3(a, b, c int) int {
        if b < a {
                a = b
        }
        if c < a {
                a = c
        }
        return a
}

// fuzzyThreshold mirrors "how many typos a human makes": 2 edits base, 3 for
// longer drug names (10+ runes) — كاربيمازول→كانبيبالول = 3.
func fuzzyThreshold(nameLen int) int {
        if nameLen >= 10 {
                return 3
        }
        return 2
}

type fuzzyHit struct {
        id    string
        score float64
}

// searchFuzzyTier2 scans the pharmacy catalog in-process. Runs only when
// tier 1 under-filled the response, so steady-state traffic never pays for it.
// Matching is per-WORD: real product names carry dosage suffixes
// ("كاربيمازول 200mg"), and garbling hits the drug word, not the strength.
func searchFuzzyTier2(entries []fuzzyCatalogEntry, query string, exclude map[string]struct{}, need int) []fuzzyHit {
        q := []rune(strings.ToLower(query))
        if len(q) < fuzzyMinQueryRunes {
                return nil
        }
        hits := make([]fuzzyHit, 0, need)
        for _, entry := range entries {
                if _, seen := exclude[entry.id]; seen {
                        continue
                }
                best := 0.0
                for _, field := range []string{entry.name, entry.gname} {
                        for _, word := range strings.Fields(strings.ToLower(field)) {
                                w := []rune(word)
                                if len(w) < fuzzyMinNameRunes {
                                        continue // كلمات قصيرة تغطيها البادئات والترايجرام
                                }
                                if abs(len(w)-len(q)) > fuzzyThreshold(len(w)) {
                                        continue // بوابة طول رخيصة قبل حساب المسافة
                                }
                                dist := levenshtein(w, q)
                                if dist > fuzzyThreshold(len(w)) {
                                        continue
                                }
                                if score := 1.0 - float64(dist)/float64(max(len(w), len(q))); score > best {
                                        best = score
                                }
                        }
                }
                if best > 0 {
                        hits = append(hits, fuzzyHit{id: entry.id, score: best})
                }
        }
        sort.Slice(hits, func(i, j int) bool { return hits[i].score > hits[j].score })
        if len(hits) > need {
                hits = hits[:need]
        }
        return hits
}

func abs(v int) int {
        if v < 0 {
                return -v
        }
        return v
}

func max(a, b int) int {
        if b > a {
                return b
        }
        return a
}

type posSearchMatch struct {
        id                                string
        name, genericName, barcode        string
        packagingType                     string
        unitsPerBox                       int64
        sellingPrice, partialPrice, stock int64
        matchRank                         int
        matchType                         string
        score                             float64
}

// SearchPOSProducts handles GET /pharmacy/pos/search?q=&limit=
// Cascade (rank): barcode exact → barcode prefix → name prefix → name substring
// → fuzzy name → fuzzy generic → fuzzy barcode (scanner misread).
func (h *Handler) SearchPOSProducts(c *gin.Context) {
        pharmacyID, ok := pharmacyScope(c)
        if !ok {
                return
        }

        query := strings.TrimSpace(c.Query("q"))
        runes := []rune(query)
        if len(runes) < posSearchMinQueryLen {
                c.JSON(http.StatusBadRequest, gin.H{
                        "error":   "query_too_short",
                        "message": "اكتب حرفين على الأقل للبحث",
                })
                return
        }
        if len(runes) > posSearchMaxQueryLen {
                query = string(runes[:posSearchMaxQueryLen])
        }

        limit := posSearchDefaultLimit
        if raw := c.Query("limit"); raw != "" {
                n := 0
                valid := raw != "0"
                for _, r := range raw {
                        if r < '0' || r > '9' {
                                valid = false
                                break
                        }
                        n = n*10 + int(r-'0')
                }
                if valid && n <= posSearchMaxLimit {
                        limit = n
                }
        }

        // Params: $1 pharmacy, $2 raw query (equality + similarity),
        // $3 trigram threshold, $4 limit, $5 LIKE-escaped query (patterns).
        // set_limit($3) applies to the % operator within this statement
        // (same connection, same snapshot) and is re-asserted on every search,
        // so pool reuse can never drift the threshold.
        rows, err := h.db.Query(c.Request.Context(), `
                WITH s AS (SELECT set_limit($3::real))
                SELECT pp.id::text,
                       COALESCE(gp.name::text, ''),
                       COALESCE(gp.generic_name::text, ''),
                       COALESCE(gp.barcode::text, ''),
                       COALESCE(pp.packaging_type::text, ''),
                       COALESCE(pp.units_per_box::int8, 1),
                       pp.selling_price::int8,
                       COALESCE(pp.partial_selling_price::int8, 0),
                       ROUND(COALESCE(SUM(ci.quantity), 0))::int8,
                       CASE
                           WHEN gp.barcode = $2 THEN 0
                           WHEN gp.barcode LIKE $5 || '%' THEN 1
                           WHEN gp.name ILIKE $5 || '%' THEN 2
                           WHEN gp.name ILIKE '%' || $5 || '%' THEN 3
                           WHEN gp.name % $2 THEN 4
                           WHEN gp.generic_name % $2 THEN 5
                           ELSE 6
                       END AS match_rank,
                       CASE
                           WHEN gp.barcode = $2 THEN 'barcode_exact'
                           WHEN gp.barcode LIKE $5 || '%' THEN 'barcode_prefix'
                           WHEN gp.name ILIKE $5 || '%' THEN 'name_prefix'
                           WHEN gp.name ILIKE '%' || $5 || '%' THEN 'name_substring'
                           WHEN gp.name % $2 THEN 'name_fuzzy'
                           WHEN gp.generic_name % $2 THEN 'generic_fuzzy'
                           ELSE 'barcode_fuzzy'
                       END AS match_type,
                       GREATEST(
                           similarity(gp.name, $2),
                           word_similarity($2, gp.name),
                           similarity(gp.generic_name, $2),
                           word_similarity($2, gp.generic_name),
                           similarity(gp.barcode, $2)
                       )::float8 AS score
                FROM pharmacy_products pp
                JOIN global_products gp ON gp.id = pp.global_product_id
                LEFT JOIN current_inventory ci ON ci.pharmacy_product_id = pp.id
                CROSS JOIN s
                WHERE pp.pharmacy_id = $1
                  AND pp.is_active = true
                  AND (
                      gp.barcode = $2
                      OR gp.barcode LIKE $5 || '%'
                      OR gp.name ILIKE $5 || '%'
                      OR gp.name ILIKE '%' || $5 || '%'
                      OR gp.name % $2
                      OR gp.generic_name % $2
                      OR gp.barcode % $2
                  )
                GROUP BY pp.id, gp.name, gp.generic_name, gp.barcode, pp.packaging_type,
                         pp.units_per_box, pp.selling_price, pp.partial_selling_price
                ORDER BY
                    match_rank,
                    score DESC,
                    gp.name
                LIMIT $4
        `, pharmacyID, query, posFuzzyThreshold, limit, escapeLike(query))
        if err != nil {
                log.Printf("[POS_SEARCH] query error: %v", err)
                c.JSON(http.StatusInternalServerError, gin.H{"error": "pos_search_failed", "message": "تعذر تنفيذ البحث"})
                return
        }
        defer rows.Close()

        results := make([]gin.H, 0, limit)
        for rows.Next() {
                var m posSearchMatch
                if err := rows.Scan(&m.id, &m.name, &m.genericName, &m.barcode, &m.packagingType,
                        &m.unitsPerBox, &m.sellingPrice, &m.partialPrice, &m.stock, &m.matchRank, &m.matchType, &m.score); err != nil {
                        log.Printf("[POS_SEARCH] scan error: %v", err)
                        c.JSON(http.StatusInternalServerError, gin.H{"error": "pos_search_failed", "message": "تعذر قراءة نتائج البحث"})
                        return
                }
                results = append(results, gin.H{
                        "id":                             m.id,
                        "name":                           m.name,
                        "generic_name":                   m.genericName,
                        "barcode":                        m.barcode,
                        "packaging_type":                 m.packagingType,
                        "units_per_box":                  m.unitsPerBox,
                        "selling_price_piastres":         m.sellingPrice,
                        "partial_selling_price_piastres": m.partialPrice,
                        "stock":                          m.stock,
                        "match_type":                     m.matchType,
                        "score":                          m.score,
                })
        }
        if err := rows.Err(); err != nil {
                log.Printf("[POS_SEARCH] rows error: %v", err)
                c.JSON(http.StatusInternalServerError, gin.H{"error": "pos_search_failed", "message": "تعذر قراءة نتائج البحث"})
                return
        }

        // Tier 2 — only when tier 1 under-filled the page: in-process levenshtein
        // over the pharmacy's own catalog (30s cache, no money/stock from cache).
        if len(results) < limit && len([]rune(query)) >= fuzzyMinQueryRunes {
                results = h.appendFuzzyTier2(c, pharmacyID, query, results, limit)
        }

        c.JSON(http.StatusOK, gin.H{"data": results})
}

// appendFuzzyTier2 finds heavily-garbled matches (كاربيمازول → كانبيبالول)
// that trigram similarity cannot see, then re-fetches authoritative rows.
func (h *Handler) appendFuzzyTier2(c *gin.Context, pharmacyID, query string, results []gin.H, limit int) []gin.H {
        entries, err := getCachedFuzzyCatalog(pharmacyID, func() ([]fuzzyCatalogEntry, error) {
                rows, err := h.db.Query(c.Request.Context(), `
                        SELECT pp.id::text, COALESCE(gp.name::text, ''), COALESCE(gp.generic_name::text, '')
                        FROM pharmacy_products pp
                        JOIN global_products gp ON gp.id = pp.global_product_id
                        WHERE pp.pharmacy_id = $1 AND pp.is_active = true
                `, pharmacyID)
                if err != nil {
                        return nil, err
                }
                defer rows.Close()

                entries := make([]fuzzyCatalogEntry, 0, 256)
                for rows.Next() {
                        var e fuzzyCatalogEntry
                        if err := rows.Scan(&e.id, &e.name, &e.gname); err != nil {
                                return nil, err
                        }
                        entries = append(entries, e)
                }
                return entries, rows.Err()
        })
        if err != nil {
                // Tier 2 is an enhancement: a cache/load failure must never fail the
                // whole search — tier 1 results are already valid.
                log.Printf("[POS_SEARCH] tier2 catalog load failed: %v", err)
                return results
        }

        exclude := make(map[string]struct{}, len(results))
        for _, item := range results {
                if id, ok := item["id"].(string); ok {
                        exclude[id] = struct{}{}
                }
        }

        need := limit - len(results)
        hits := searchFuzzyTier2(entries, query, exclude, need)
        if len(hits) == 0 {
                return results
        }

        ids := make([]string, len(hits))
        scores := make(map[string]float64, len(hits))
        for i, hit := range hits {
                ids[i] = hit.id
                scores[hit.id] = hit.score
        }

        rows, err := h.db.Query(c.Request.Context(), `
                SELECT pp.id::text, COALESCE(gp.name::text, ''), COALESCE(gp.generic_name::text, ''),
                       COALESCE(gp.barcode::text, ''), COALESCE(pp.packaging_type::text, ''),
                       COALESCE(pp.units_per_box::int8, 1), pp.selling_price::int8,
                       COALESCE(pp.partial_selling_price::int8, 0),
                       ROUND(COALESCE(SUM(ci.quantity), 0))::int8
                FROM pharmacy_products pp
                JOIN global_products gp ON gp.id = pp.global_product_id
                LEFT JOIN current_inventory ci ON ci.pharmacy_product_id = pp.id
                WHERE pp.pharmacy_id = $1 AND pp.id::text = ANY($2)
                GROUP BY pp.id, gp.name, gp.generic_name, gp.barcode, pp.packaging_type,
                         pp.units_per_box, pp.selling_price, pp.partial_selling_price
        `, pharmacyID, ids)
        if err != nil {
                return results
        }
        defer rows.Close()

        fuzzyRows := make(map[string]gin.H, len(ids))
        for rows.Next() {
                var m posSearchMatch
                if err := rows.Scan(&m.id, &m.name, &m.genericName, &m.barcode, &m.packagingType,
                        &m.unitsPerBox, &m.sellingPrice, &m.partialPrice, &m.stock); err != nil {
                        return results
                }
                fuzzyRows[m.id] = gin.H{
                        "id":                             m.id,
                        "name":                           m.name,
                        "generic_name":                   m.genericName,
                        "barcode":                        m.barcode,
                        "packaging_type":                 m.packagingType,
                        "units_per_box":                  m.unitsPerBox,
                        "selling_price_piastres":         m.sellingPrice,
                        "partial_selling_price_piastres": m.partialPrice,
                        "stock":                          m.stock,
                        "match_type":                     "name_fuzzy",
                        "score":                          scores[m.id],
                }
        }
        // Keep the levenshtein ranking order (best typo match first).
        for _, id := range ids {
                if row, ok := fuzzyRows[id]; ok {
                        results = append(results, row)
                }
        }
        return results
}
