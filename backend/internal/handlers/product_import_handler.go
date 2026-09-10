package handlers

import (
        "encoding/csv"
	"encoding/json"
        "errors"
        "io"
        "mime/multipart"
        "net/http"
        "strconv"
        "strings"
        "time"
        "unicode"

        "github.com/gin-gonic/gin"
        "github.com/xuri/excelize/v2"

        "github.com/pharmacy-os/backend/internal/auth"
)

// ============================================================================
// استيراد المنتجات من ملف جداول (Excel/CSV) — ترحيل بيانات البرامج القديمة.
//
// التصميم يتبع ممارسات الاستيراد الاحترافية:
//   - خطوتان: معاينة (تحليل + ربط أعمدة مقترح تلقائيًا) ثم تنفيذ مؤكد.
//   - التحقق من كل صف قبل اللمس، والصفوف الصالحة تُرحَّل ذريًا في معاملة
//     واحدة (كلها أو لا شيء) مع تقرير بالأسباب لكل صف مرفوض.
//   - لا يُخزَّن الملف على القرص ولا حالة بين الطلبات — العميل يرسل الملف
//     مرتين (معاينة ثم تنفيذ) فيبقى النظام عديم الحالة وقابلًا للتكرار.
//   - الأرقام تقبل الأرقام العربية-الهندية (٠-٩) والفواصل العربية وفواصل
//     الآلات وعلامات العملة، والتواريخ تقبل الصيغ الشائعة في التصديرات.
// ============================================================================

const (
        importMaxFileSize = 10 << 20 // 10MB
        importMaxRows     = 5000
        importSampleRows  = 25
        importErrorCap    = 200
)

// importField — حقول الاستيراد المعروفة (المفتاح ثابت عبر الواجهة والباكند).
const (
        ifName          = "name"
        ifBarcode       = "barcode"
        ifSellingPrice  = "selling_price"
        ifCostPrice     = "cost_price"
        ifPartialPrice  = "partial_price"
        ifQuantity      = "quantity"
        ifUnitsPerBox   = "units_per_box"
        ifMinStock      = "min_stock_level"
        ifExpiry        = "expiry_date"
        ifBatch         = "batch_number"
        ifGenericName   = "generic_name"
        ifStrength      = "strength"
        ifDosageForm    = "dosage_form"
        importBatchRef  = "opening_balance"
        importBatchNote = "product_import"
)

var importFieldOrder = []string{
        ifName, ifBarcode, ifSellingPrice, ifCostPrice, ifPartialPrice, ifQuantity,
        ifUnitsPerBox, ifMinStock, ifExpiry, ifBatch, ifGenericName, ifStrength, ifDosageForm,
}

// normalizeHeaderKey — تطبيع عنوان العمود: حروف صغيرة بلا مسافات أو ترميزات.
func normalizeHeaderKey(s string) string {
        var b strings.Builder
        for _, r := range strings.ToLower(s) {
                switch r {
                case ' ', '\t', '\n', '\r', '.', '،', '(', ')', '-', '_', '/', 'ـ', ':':
                        continue
                case 'ة': r = 'ه' // teh marbuta -> ha
                case 'أ', 'إ', 'آ': r = 'ا' // alef variants
                case 'ى': r = 'ي' // alef maqsura -> ya
                case 'ؤ': r = 'و'
                case 'ئ': r = 'ي'
                }
                b.WriteRune(r)
        }
        return b.String()
}

// importHeaderSynonyms — مطابقة تامة بعد التطبيع (أول مطابقة تفوز).
var importHeaderSynonyms = map[string]string{
        // الاسم
        "اسمالصنف": ifName, "اسمالمنتج": ifName, "الصنف": ifName, "المنتج": ifName,
        "الاسم": ifName, "اسمالدواء": ifName, "اسم": ifName, "اسمالتول": ifName,
        "name": ifName, "product": ifName, "productname": ifName, "item": ifName, "itemname": ifName,
        // الباركود
        "الباركود": ifBarcode, "باركود": ifBarcode, "باركودالصنف": ifBarcode, "الكود": ifBarcode,
        "barcode": ifBarcode, "barcode1": ifBarcode, "code": ifBarcode,
        // سعر البيع
        "سعرالبيع": ifSellingPrice, "السعر": ifSellingPrice, "سعر": ifSellingPrice,
        "سعرالوحدة": ifSellingPrice, "سعرالصرف": ifSellingPrice, "سعرالجملة": ifSellingPrice,
        "price": ifSellingPrice, "sellingprice": ifSellingPrice, "unitprice": ifSellingPrice,
        // سعر الشراء/التكلفة
        "سعرالشراء": ifCostPrice, "التكلفة": ifCostPrice, "سعرالتكلفة": ifCostPrice,
        "تكلفة": ifCostPrice, "cost": ifCostPrice, "costprice": ifCostPrice, "purchaseprice": ifCostPrice,
        // سعر الشريط
        "سعرالشريط": ifPartialPrice, "سعرالشرائط": ifPartialPrice, "سعرالشريطالمفرد": ifPartialPrice,
        "stripprice": ifPartialPrice,
        // الكمية
        "الكمية": ifQuantity, "الرصيد": ifQuantity, "الموجود": ifQuantity, "المتاح": ifQuantity,
        "الكميةالحالية": ifQuantity, "الرصيدالحالي": ifQuantity, "الكميةالمتاحة": ifQuantity,
        "quantity": ifQuantity, "qty": ifQuantity, "stock": ifQuantity, "balance": ifQuantity,
        // الشرائط بالعلبة
        "عددالشرائط": ifUnitsPerBox, "الشرائطبالعلبة": ifUnitsPerBox, "عددالشرائطفيالعلبة": ifUnitsPerBox,
        "شرائطالعلبة": ifUnitsPerBox, "unitsperbox": ifUnitsPerBox, "stripsperbox": ifUnitsPerBox,
        "عدد الشرائط بالعلبة": ifUnitsPerBox, "عدد الشرائط بالعلبه": ifUnitsPerBox, "شرائط بالعلبه": ifUnitsPerBox,
        // حد الطلب
        "حدالطلب": ifMinStock, "الحدالادنى": ifMinStock, "الحدالأدنى": ifMinStock,
        "حدالاعداد": ifMinStock, "حدامان": ifMinStock, "minstock": ifMinStock,
        "minstocklevel": ifMinStock, "reorderlevel": ifMinStock,
        // الصلاحية
        "الصلاحية": ifExpiry, "تاريخالانتهاء": ifExpiry, "تاريخالصلاحية": ifExpiry,
        "انتهاءالصلاحية": ifExpiry, "expiry": ifExpiry, "expirydate": ifExpiry, "exp": ifExpiry, "expdate": ifExpiry,
        // التشغيلة
        "التشغيلة": ifBatch, "رقمالتشغيلة": ifBatch, "التشغيله": ifBatch,
        "رقمالوتش": ifBatch, "batch": ifBatch, "batchnumber": ifBatch, "lot": ifBatch, "lotnumber": ifBatch,
        // الاسم العلمي
        "الاسمالعلمي": ifGenericName, "اسمالعلمي": ifGenericName, "التركيب": ifGenericName,
        "المادةالفعالة": ifGenericName, "المادهالفعاله": ifGenericName, "genericname": ifGenericName,
        "scientificname": ifGenericName,
        // التركيز
        "التركيز": ifStrength, "التركيزات": ifStrength, "strength": ifStrength,
        // الشكل الصيدلي
        "الشكلالصيدلي": ifDosageForm, "شكلالجرعة": ifDosageForm, "شكلالجرعه": ifDosageForm,
        "dosageform": ifDosageForm, "الشكل": ifDosageForm,
}

// importHeaderSynonymsNorm — نسخة مطبعة من المرادفات (تطبّع مرة عند الإقلاع).
var importHeaderSynonymsNorm = func() map[string]string {
    m := make(map[string]string, len(importHeaderSynonyms))
    for k, v := range importHeaderSynonyms {
        m[normalizeHeaderKey(k)] = v
    }
    return m
}()

// suggestImportMapping — يبني خريطة ربط مقترحة: اسم الحقل → فهرس العمود (-1 لو غير موجود).
// المرحلة 1: مطابقة تامة بعد التطبيع. المرحلة 2: قواعد كلمات مفتاحية للأعمدة غير المطابقة.
func suggestImportMapping(headers []string) map[string]int {
        mapping := make(map[string]int, len(importFieldOrder))
        used := make(map[int]bool)
        for _, f := range importFieldOrder {
                mapping[f] = -1
        }
        normalized := make([]string, len(headers))
        for i, h := range headers {
                normalized[i] = normalizeHeaderKey(h)
        }
        // المرحلة 1
        for i, nh := range normalized {
                if nh == "" || used[i] {
                        continue
                }
                if field, ok := importHeaderSynonymsNorm[nh]; ok && mapping[field] == -1 {
                        mapping[field] = i
                        used[i] = true
                }
        }
        // المرحلة 2: قواعد مرنة للأعمدة غير المطابقة تامًا (أكثر خصوصية أولاً — كل مجموعة = بدائل OR)
        rules := []struct {
            field   string
            require [][]string
            exclude []string
        } {
            {ifPartialPrice, [][]string{{"سعر"}, {"شريط", "شرائط"}}, nil},
            {ifUnitsPerBox, [][]string{{"شريط", "شرائط"}, {"علب", "عله"}}, nil},
            {ifMinStock, [][]string{{"حد"}}, []string{"شرائط", "شريط"}},
            {ifExpiry, [][]string{{"صلاح", "انتهاء"}}, nil},
            {ifBatch, [][]string{{"تشغيل", "وتش"}}, nil},
            {ifCostPrice, [][]string{{"شراء", "تكلف"}}, nil},
            {ifSellingPrice, [][]string{{"بيع", "صرف"}}, nil},
            {ifSellingPrice, [][]string{{"سعر"}}, []string{"شراء", "تكلف", "شريط", "شرائط"}},
            {ifQuantity, [][]string{{"كمية", "رصيد", "موجود"}}, nil},
            {ifGenericName, [][]string{{"علمي", "تركيب"}}, nil},
            {ifStrength, [][]string{{"تركيز"}}, nil},
            {ifDosageForm, [][]string{{"شكل"}}, nil},
            {ifBarcode, [][]string{{"باركود"}}, nil},
            {ifName, [][]string{{"اسم", "صنف", "منتج", "name"}}, []string{"علمي", "شريط", "شرائط", "مستخدم", "عميل"}},
        }
        for _, rule := range rules {
            if mapping[rule.field] != -1 {
                continue
            }
            for i, nh := range normalized {
                if nh == "" || used[i] {
                    continue
                }
                ok := true
                for _, group := range rule.require {
                    hit := false
                    for _, kw := range group {
                        if strings.Contains(nh, kw) {
                        	hit = true
                        	break
                        }
                    }
                    if !hit {
                        ok = false
                        break
                    }
                }
                if ok {
                    for _, ex := range rule.exclude {
                        if strings.Contains(nh, ex) {
                        	ok = false
                        	break
                        }
                    }
                }
                if ok {
                    mapping[rule.field] = i
                    used[i] = true
                    break
                }
            }
        }
        return mapping
}
// parseArabicNumber — يحلل رقمًا قد يحتوي أرقامًا عربية-هندية، فواصل آلاف،
// فواصل عشرية عربية، أو لاحقة عملة («50 ج»، «1,250.75»، «١٢٫٥»).
func parseArabicNumber(raw string) (float64, bool) {
        s := strings.TrimSpace(raw)
        if s == "" {
                return 0, false
        }
        // الأرقام العربية-الهندية والفارسية
        var b strings.Builder
        for _, r := range s {
                switch {
                case r >= 0x0660 && r <= 0x0669: // ٠-٩
                        b.WriteRune(rune('0' + (r - 0x0660)))
                case r >= 0x06F0 && r <= 0x06F9: // ۰-۹
                        b.WriteRune(rune('0' + (r - 0x06F0)))
                case r == 0x066B: // ٫ فاصلة عشرية عربية
                        b.WriteByte('.')
                case r == 0x066C || r == '،': // ٬ فاصلة آلاف عربية
                        // تجاهل — فاصل آلاف
                default:
                        b.WriteRune(r)
                }
        }
        s = b.String()
        // لاحقات العملة الشائعة
        for _, token := range []string{"ج.م", "جنيه", "ج.م.", "ج", "مصر", "EGP", "egp", "LE", "L.E", "le", "GBP"} {
                s = strings.ReplaceAll(s, token, "")
        }
        s = strings.Map(func(r rune) rune {
                if unicode.IsSpace(r) || r == ',' || r == '\u00A0' {
                        return -1
                }
                return r
        }, s)
        if s == "" {
                return 0, false
        }
        if strings.Count(s, ".") > 1 {
                return 0, false
        }
        v, err := strconv.ParseFloat(s, 64)
        if err != nil {
                return 0, false
        }
        return v, true
}

// egpToPiastres — يحول جنيهًا عشريًا إلى قروش (أقرب قرش).
func egpToPiastres(v float64) int64 {
        if v < 0 {
                return -1
        }
        return int64(v*100 + 0.5)
}

var importDateLayouts = []string{
        "2006-01-02", "2006/01/02", "02/01/2006", "2/1/2006", "02-01-2006",
        "02.01.2006", "02/01/06", "02/1/06", "1/2/2006", "02-Jan-2006", "02-Jan-06",
}

// parseImportDate — يفهم صيغ التواريخ الشائعة في تصديرات البرامج القديمة.
func parseImportDate(raw string) (time.Time, bool) {
        s := strings.TrimSpace(raw)
        if s == "" {
                return time.Time{}, false
        }
        // أرقام عربية-هندية في التواريخ
        s = strings.Map(func(r rune) rune {
                if r >= 0x0660 && r <= 0x0669 {
                        return rune('0' + (r - 0x0660))
                }
                return r
        }, s)
        for _, layout := range importDateLayouts {
                if t, err := time.Parse(layout, s); err == nil {
                        return t, true
                }
        }
        // تسلسلي إكسل (رقم كبير بلا فواصل)
        if v, err := strconv.ParseFloat(s, 64); err == nil && v >= 20000 && v <= 80000 {
                if t, err := excelize.ExcelDateToTime(v, false); err == nil {
                        return t, true
                }
        }
        return time.Time{}, false
}

var importDosageFormMap = map[string]string{
        "أقراص": "tablet", "اقراص": "tablet", "tablet": "tablet", "tablets": "tablet",
        "كبسولات": "capsule", "كبسولة": "capsule", "capsule": "capsule", "capsules": "capsule",
        "شراب": "syrup", "syrup": "syrup", "syrups": "syrup",
        "نقط": "drop", "قطرة": "drop", "drops": "drop", "drop": "drop",
        "حقن": "injection", "حقنة": "injection", "injection": "injection",
        "مرهم": "ointment", "مراهم": "ointment", "ointment": "ointment",
        "كريم": "cream", "cream": "cream",
        "جل": "gel", "gel": "gel",
        "بودرة": "powder", "مسحوق": "powder", "powder": "powder",
        "محلول": "solution", "solution": "solution",
        "معلق": "suspension", "suspension": "suspension",
        "بخاخ": "nasal_spray", "spray": "nasal_spray",
        "تحاميل": "suppository", "suppository": "suppository",
        "بخاخ_عين": "eye_drops", "نقط_عين": "eye_drops",
        "لصقات": "patch", "patch": "patch",
        "بخاخ_استنشاق": "inhaler", "inhaler": "inhaler",
        "أخرى": "other", "other": "other",
}

// mapImportDosageForm — يحوّل الشكل الصيدلي النصي لقيمة enum معروفة؛ المجهول يعود tablet.
func mapImportDosageForm(raw string) string {
        if raw == "" {
                return "tablet"
        }
        if v, ok := importDosageFormMap[strings.ToLower(strings.TrimSpace(raw))]; ok {
                return v
        }
        if v, ok := importDosageFormMap[strings.TrimSpace(raw)]; ok {
                return v
        }
        return "tablet"
}

// cell — قراءة آمنة لخلية قد تكون فائدة القص في صفوف xlsx غير المتساوية.
func cell(row []string, idx int) string {
        if idx < 0 || idx >= len(row) {
                return ""
        }
        return strings.TrimSpace(row[idx])
}

// parseImportFile — يحلل ملف xlsx أو csv ويعيد الترويسة وصفوف البيانات.
func parseImportFile(fh *multipart.FileHeader) (headers []string, rows [][]string, fileType string, err error) {
        if fh.Size > importMaxFileSize {
                return nil, nil, "", errors.New("file_too_large")
        }
        ext := strings.ToLower(fh.Filename)
        fileType = ""
        switch {
        case strings.HasSuffix(ext, ".xlsx"):
                fileType = "xlsx"
        case strings.HasSuffix(ext, ".csv"), strings.HasSuffix(ext, ".txt"):
                fileType = "csv"
        default:
                return nil, nil, "", errors.New("unsupported_format")
        }

        f, err := fh.Open()
        if err != nil {
                return nil, nil, "", errors.New("cannot_read_file")
        }
        defer func() { _ = f.Close() }()

        if fileType == "xlsx" {
                xf, err := excelize.OpenReader(io.LimitReader(f, importMaxFileSize+1))
                if err != nil {
                        return nil, nil, "", errors.New("invalid_xlsx")
                }
                defer func() { _ = xf.Close() }()
                sheet := xf.GetSheetName(0)
                all, err := xf.GetRows(sheet)
                if err != nil {
                        return nil, nil, "", errors.New("invalid_xlsx")
                }
                for _, r := range all {
                        trimmed := make([]string, len(r))
                        nonEmpty := 0
                        for i, c := range r {
                                trimmed[i] = strings.TrimSpace(c)
                                if trimmed[i] != "" {
                                        nonEmpty++
                                }
                        }
                        if nonEmpty == 0 {
                                continue // صف فارغ
                        }
                        rows = append(rows, trimmed)
                }
        } else {
                data, err := io.ReadAll(io.LimitReader(f, importMaxFileSize+1))
                if err != nil {
                        return nil, nil, "", errors.New("cannot_read_file")
                }
                // إزالة BOM إن وُجد (تصديرات Excel UTF-8)
                data = []byte(strings.TrimPrefix(string(data), "\uFEFF"))
                // شمّ الفاصل: الفاصلة العادية أم الفاصلة المنقوطة أم جدولة
                firstLine := data
                if i := strings.IndexAny(string(data), "\r\n"); i >= 0 {
                        firstLine = data[:i]
                }
                fl := string(firstLine)
                comma := rune(',')
                if strings.Count(fl, ";") > strings.Count(fl, ",") {
                        comma = ';'
                } else if strings.Count(fl, "\t") > strings.Count(fl, ",") {
                        comma = '\t'
                }
                cr := csv.NewReader(strings.NewReader(string(data)))
                cr.Comma = comma
                cr.LazyQuotes = true
                cr.FieldsPerRecord = -1
                parsed, err := cr.ReadAll()
                if err != nil {
                        return nil, nil, "", errors.New("invalid_csv")
                }
                for _, r := range parsed {
                        trimmed := make([]string, len(r))
                        nonEmpty := 0
                        for i, c := range r {
                                trimmed[i] = strings.TrimSpace(c)
                                if trimmed[i] != "" {
                                        nonEmpty++
                                }
                        }
                        if nonEmpty == 0 {
                                continue
                        }
                        rows = append(rows, trimmed)
                }
        }

        if len(rows) == 0 {
                return nil, nil, "", errors.New("empty_file")
        }
        // الترويسة: أول صف فيه خليتين غير فارغتين على الأقل
        headerIdx := 0
        for i, r := range rows {
                nonEmpty := 0
                for _, c := range r {
                        if c != "" {
                                nonEmpty++
                        }
                }
                if nonEmpty >= 2 {
                        headerIdx = i
                        break
                }
        }
        headers = rows[headerIdx]
        dataRows := rows[headerIdx+1:]
        if len(dataRows) > importMaxRows {
                dataRows = dataRows[:importMaxRows]
        }
        return headers, dataRows, fileType, nil
}

// PreviewProductImport — الخطوة 1: POST /pharmacy/imports/products/preview
// يستقبل الملف ويعيد الترويسة + الربط المقترح + عينة صفوف + تقدير الصلاحية.
func (h *Handler) PreviewProductImport(c *gin.Context) {
        principal, ok := auth.PrincipalFromContext(c)
        if !ok || principal.PharmacyID == "" {
                c.JSON(http.StatusForbidden, gin.H{"error": "pharmacy_account_required", "message": "حساب صيدلية مطلوب"})
                return
        }
        fh, err := c.FormFile("file")
        if err != nil {
                c.JSON(http.StatusBadRequest, gin.H{"error": "file_required", "message": "يرجى رفع ملف Excel (xlsx) أو CSV"})
                return
        }
        headers, rows, fileType, perr := parseImportFile(fh)
        if perr != nil {
                msg := map[string]string{
                        "file_too_large":    "حجم الملف أكبر من 10 ميجابايت",
                        "unsupported_format": "صيغة غير مدعومة — يُقبل Excel بصيغة xlsx أو ملف CSV (الصيغة xls القديمة يُرجى حفظها كـ xlsx أولًا)",
                        "invalid_xlsx":      "الملف ليس ملف Excel صالحًا",
                        "invalid_csv":       "ملف CSV غير صالح",
                        "empty_file":        "الملف لا يحتوي بيانات",
                        "cannot_read_file":  "تعذرت قراءة الملف",
                }[perr.Error()]
                if msg == "" {
                        msg = "تعذر تحليل الملف"
                }
                c.JSON(http.StatusBadRequest, gin.H{"error": perr.Error(), "message": msg})
                return
        }

        mapping := suggestImportMapping(headers)
        // لو أرسل العميل ربطًا مخصصًا (بعد تعديله في الواجهة) نستخدمه مع إعادة التقدير
        if override := strings.TrimSpace(c.PostForm("mapping")); override != "" {
        	var custom map[string]int
        	if err := json.Unmarshal([]byte(override), &custom); err == nil {
        		for f, idx := range custom {
        			if idx >= len(headers) {
        				idx = -1
        			}
        			mapping[f] = idx
        		}
        	}
        }
        // عينة الصفوف + تقدير الصلاحية على الربط المقترح
        sample := rows
        if len(sample) > importSampleRows {
                sample = sample[:importSampleRows]
        }
        valid, invalid := 0, 0
        for _, r := range rows {
                if _, verr := validateImportRow(r, mapping, importOptions{QuantityUnit: "box", DuplicateStrategy: "skip"}); verr == "" {
                        valid++
                } else {
                        invalid++
                }
        }

        c.JSON(http.StatusOK, gin.H{"data": gin.H{
                "file_type":       fileType,
                "total_rows":      len(rows),
                "headers":         headers,
                "mapping":         mapping,
                "rows":            sample,
                "valid_estimate":  valid,
                "invalid_estimate": invalid,
                "max_rows":        importMaxRows,
        }})
}
