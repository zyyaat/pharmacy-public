"use client";

// Library detail — the admin's cockpit for ONE library: its products with
// the official price per entry, the release change log (the same log the
// pharmacy diff renders in Phase 2), and library settings. Publishing
// follows the backend semantics: first publish releases v1, later
// publishes cut a new version from the accumulated draft changes and
// refuse when nothing changed.

import React, { useCallback, useEffect, useMemo, useState } from "react";
import { useParams, useRouter } from "next/navigation";
import {
  ArrowLeft, Upload, Plus, Pencil, Trash2, Globe2, BadgeCheck,
  PackageSearch, History, Settings2, Send,
} from "lucide-react";
import { toast } from "sonner";
import { Card, CardContent, Button, Input, Badge } from "@/components/ui";
import { Table, TableHeader, TableBody, TableRow, TableHead, TableCell } from "@/components/ui/table";
import { Modal } from "@/components/ui/modal";
import {
  librariesApi, ApiError,
  type LibraryRow, type LibraryProductRow, type LibraryChangeRow,
  type CatalogProductRow, type LibraryImportPreview, type LibraryImportReport,
} from "@/lib/api";
import { useT } from "@/i18n/provider";
import { fmtDate, fmtNumber } from "@/i18n/format";

type Tab = "products" | "changes" | "settings";

const DOSAGE_FORMS = ["tablet", "capsule", "syrup", "drop", "injection", "ointment", "cream", "gel", "powder", "solution", "suspension", "inhaler", "patch", "suppository", "eye_drops", "ear_drops", "nasal_spray", "other"];
const CATEGORIES = ["medication", "supplement", "medical_device", "personal_care", "cosmetic", "food_supplement", "herbal", "vaccine", "consumable", "other"];
const COUNTRY_OPTIONS = ["EG", "SA", "AE", "KW", "QA", "OM", "BH", "JO", "MA", "DZ", "TN", "LY", "SD"];
const CURRENCY_OPTIONS = ["EGP", "SAR", "AED", "KWD", "QAR", "OMR", "BHD", "JOD", "USD", "EUR"];

const money = (p: number | null | undefined) => (p === null || p === undefined ? "—" : fmtNumber(p / 100));

export default function LibraryDetailPage() {
  const { id } = useParams<{ id: string }>();
  const router = useRouter();
  const t = useT("libraries");
  const [lib, setLib] = useState<LibraryRow | null>(null);
  const [notFound, setNotFound] = useState(false);
  const [tab, setTab] = useState<Tab>("products");
  const [publishing, setPublishing] = useState(false);
  const [reloadKey, setReloadKey] = useState(0);

  useEffect(() => {
    const stored = new URLSearchParams(window.location.search).get("tab") as Tab | null;
    if (stored === "changes" || stored === "settings") setTab(stored);
  }, []);

  const switchTab = (next: Tab) => {
    setTab(next);
    window.history.replaceState(null, "", `/libraries/${id}?tab=${next}`);
  };

  const reloadLib = useCallback(async () => {
    try {
      setLib(await librariesApi.get(id));
    } catch (e) {
      if (e instanceof ApiError && e.status === 404) setNotFound(true);
      else toast.error(e instanceof ApiError && e.message ? e.message : t("error_load"));
    }
  }, [id, t]);

  useEffect(() => {
    void reloadLib();
  }, [reloadLib, reloadKey]);

  const bump = () => {
    setReloadKey((k) => k + 1);
    void reloadLib();
  };

  const publish = async () => {
    setPublishing(true);
    try {
      const res = await librariesApi.publish(id);
      toast.success(res.first_publish ? t("ok_published_first", { v: res.version }) : t("ok_published", { v: res.version }));
      bump();
    } catch (e) {
      toast.error(e instanceof ApiError && e.message ? e.message : t("error_publish"));
    } finally {
      setPublishing(false);
    }
  };

  if (notFound) {
    return (
      <div className="p-10 text-center space-y-3">
        <p className="text-lg font-semibold">{t("not_found")}</p>
        <Button variant="outline" onClick={() => router.push("/libraries")}>
          <ArrowLeft className="h-4 w-4" />{t("btn_back")}
        </Button>
      </div>
    );
  }

  const tabs: Array<{ key: Tab; label: string; icon: React.ReactNode }> = [
    { key: "products", label: t("tab_products"), icon: <PackageSearch className="h-4 w-4" /> },
    { key: "changes", label: t("tab_changes"), icon: <History className="h-4 w-4" /> },
    { key: "settings", label: t("tab_settings"), icon: <Settings2 className="h-4 w-4" /> },
  ];

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div className="space-y-1.5">
          <Button variant="ghost" size="sm" onClick={() => router.push("/libraries")}>
            <ArrowLeft className="h-4 w-4" />{t("btn_back")}
          </Button>
          <h1 className="text-2xl font-bold flex items-center gap-2 flex-wrap">
            {lib?.name ?? "…"}
            {lib ? (
              lib.is_published ? (
                <Badge className="bg-emerald-100 text-emerald-700 dark:bg-emerald-900/40 dark:text-emerald-300">
                  {t("badge_published")} · {t("version_short", { v: lib.version })}
                </Badge>
              ) : (
                <Badge variant="secondary">{t("badge_draft")}</Badge>
              )
            ) : null}
            {lib?.country_code ? (
              <Badge variant="outline">{lib.country_code} · {lib.currency}</Badge>
            ) : (
              <Badge variant="outline" className="gap-1">
                <Globe2 className="h-3 w-3" />{t("badge_global")}
              </Badge>
            )}
          </h1>
          {lib?.description ? <p className="text-sm text-muted-foreground">{lib.description}</p> : null}
        </div>
        {lib ? (
          <Button variant="gradient" loading={publishing} onClick={publish}>
            <Send className="h-4 w-4" />
            {lib.is_published
              ? t("btn_publish_new", { v: lib.version + 1 })
              : t("btn_publish_first")}
            {lib.draft_changes > 0 ? (
              <span className="ms-1 opacity-80">({fmtNumber(lib.draft_changes)})</span>
            ) : null}
          </Button>
        ) : null}
      </div>

      <div className="border-b flex gap-1">
        {tabs.map((tb) => (
          <button
            key={tb.key}
            onClick={() => switchTab(tb.key)}
            className={`flex items-center gap-1.5 px-4 py-2.5 text-sm font-medium border-b-2 -mb-px transition-colors ${
              tab === tb.key
                ? "border-emerald-600 text-emerald-700 dark:text-emerald-400"
                : "border-transparent text-muted-foreground hover:text-foreground"
            }`}
          >
            {tb.icon}
            {tb.label}
          </button>
        ))}
      </div>

      {tab === "products" ? <ProductsTab libraryId={id} lib={lib} onChanged={bump} /> : null}
      {tab === "changes" ? <ChangesTab libraryId={id} /> : null}
      {tab === "settings" ? <SettingsTab lib={lib} onSaved={bump} onDeleted={() => router.push("/libraries")} /> : null}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Products tab
// ---------------------------------------------------------------------------

function ProductsTab({ libraryId, lib, onChanged }: { libraryId: string; lib: LibraryRow | null; onChanged: () => void }) {
  const t = useT("libraries");
  const [items, setItems] = useState<LibraryProductRow[]>([]);
  const [pagination, setPagination] = useState({ total: 0, page: 1, page_size: 20, total_pages: 1 });
  const [search, setSearch] = useState("");
  const [page, setPage] = useState(1);
  const [loading, setLoading] = useState(true);

  const [editing, setEditing] = useState<LibraryProductRow | null>(null);
  const [editPrice, setEditPrice] = useState("");
  const [saving, setSaving] = useState(false);
  const [removing, setRemoving] = useState<LibraryProductRow | null>(null);
  const [removeBusy, setRemoveBusy] = useState(false);
  const [addOpen, setAddOpen] = useState(false);
  const [importOpen, setImportOpen] = useState(false);

  const reload = useCallback(async () => {
    setLoading(true);
    try {
      const res = await librariesApi.products(libraryId, search, page);
      setItems(res.items);
      setPagination(res.pagination);
    } catch (e) {
      toast.error(e instanceof ApiError && e.message ? e.message : t("error_load"));
    } finally {
      setLoading(false);
    }
  }, [libraryId, search, page, t]);

  useEffect(() => {
    void reload();
  }, [reload]);

  const savePrice = async () => {
    if (!editing) return;
    const piastres = Math.round(parseFloat(editPrice.replace(",", ".")) * 100);
    if (isNaN(piastres) || piastres < 0) {
      toast.error(t("err_invalid_price"));
      return;
    }
    setSaving(true);
    try {
      await librariesApi.updateProduct(libraryId, editing.id, { official_price_piastres: piastres });
      toast.success(t("ok_price_updated"));
      setEditing(null);
      onChanged();
      await reload();
    } catch (e) {
      toast.error(e instanceof ApiError && e.message ? e.message : t("error_save"));
    } finally {
      setSaving(false);
    }
  };

  const confirmRemove = async () => {
    if (!removing) return;
    setRemoveBusy(true);
    try {
      await librariesApi.removeProduct(libraryId, removing.id);
      toast.success(t("ok_removed"));
      setRemoving(null);
      onChanged();
      await reload();
    } catch (e) {
      toast.error(e instanceof ApiError && e.message ? e.message : t("error_delete"));
    } finally {
      setRemoveBusy(false);
    }
  };

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <Input
          className="max-w-xs"
          placeholder={t("ph_search_products")}
          value={search}
          onChange={(e) => { setSearch(e.target.value); setPage(1); }}
        />
        <div className="flex gap-2">
          <Button variant="outline" onClick={() => setImportOpen(true)}>
            <Upload className="h-4 w-4" />{t("btn_import")}
          </Button>
          <Button variant="gradient" onClick={() => setAddOpen(true)}>
            <Plus className="h-4 w-4" />{t("btn_add_product")}
          </Button>
        </div>
      </div>

      <Card>
        <CardContent className="p-0">
          {loading ? (
            <p className="p-6 text-sm text-muted-foreground">{t("loading")}</p>
          ) : items.length === 0 ? (
            <p className="p-10 text-center text-sm text-muted-foreground">
              {search ? t("empty_search") : t("empty_products")}
            </p>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>{t("col_product")}</TableHead>
                  <TableHead>{t("col_barcode")}</TableHead>
                  <TableHead>{t("col_official_price")}</TableHead>
                  <TableHead>{t("col_state")}</TableHead>
                  <TableHead>{t("col_actions")}</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {items.map((p) => (
                  <TableRow key={p.id}>
                    <TableCell>
                      <div className="font-medium flex items-center gap-1.5">
                        {p.name}
                        {p.is_verified ? (
                          <BadgeCheck className="h-4 w-4 text-emerald-600" aria-label={t("verified")} />
                        ) : null}
                      </div>
                      <div className="text-xs text-muted-foreground">
                        {[p.generic_name, p.strength, t(`dosage_${p.dosage_form}`), p.manufacturer_name]
                          .filter(Boolean).join(" · ")}
                      </div>
                    </TableCell>
                    <TableCell dir="ltr" className="text-xs">{p.barcode ?? "—"}</TableCell>
                    <TableCell>
                      <span className="font-medium">{money(p.official_price_piastres)}</span>
                      <span className="text-xs text-muted-foreground"> {lib?.currency ?? ""}</span>
                    </TableCell>
                    <TableCell>
                      {p.product_category ? (
                        <Badge variant="outline">{t(`category_${p.product_category}`)}</Badge>
                      ) : null}
                    </TableCell>
                    <TableCell>
                      <div className="flex items-center gap-1">
                        <Button variant="ghost" size="sm" onClick={() => { setEditing(p); setEditPrice((p.official_price_piastres / 100).toString()); }}>
                          <Pencil className="h-4 w-4" />{t("btn_price")}
                        </Button>
                        <Button variant="ghost" size="sm" className="text-red-600 hover:text-red-700" onClick={() => setRemoving(p)}>
                          <Trash2 className="h-4 w-4" />{t("btn_remove")}
                        </Button>
                      </div>
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
        </CardContent>
      </Card>

      {pagination.total_pages > 1 ? (
        <div className="flex items-center justify-between text-sm">
          <span className="text-muted-foreground">{t("pagination", { shown: items.length, total: fmtNumber(pagination.total) })}</span>
          <div className="flex gap-2">
            <Button variant="outline" size="sm" disabled={page <= 1} onClick={() => setPage((p) => p - 1)}>{t("btn_prev")}</Button>
            <Button variant="outline" size="sm" disabled={page >= pagination.total_pages} onClick={() => setPage((p) => p + 1)}>{t("btn_next")}</Button>
          </div>
        </div>
      ) : null}

      {/* price edit modal */}
      <Modal isOpen={editing !== null} onClose={() => setEditing(null)}>
        <div className="space-y-4 p-6">
          <h2 className="text-lg font-bold">{t("price_title", { name: editing?.name ?? "" })}</h2>
          <div className="space-y-1.5">
            <label className="text-sm font-medium">{t("fld_official_price")} ({lib?.currency ?? ""})</label>
            <Input dir="ltr" inputMode="decimal" value={editPrice} onChange={(e) => setEditPrice(e.target.value)} />
          </div>
          <p className="text-xs text-muted-foreground">{t("hint_price_change")}</p>
          <div className="flex justify-end gap-2 pt-2">
            <Button variant="outline" onClick={() => setEditing(null)}>{t("btn_cancel")}</Button>
            <Button variant="gradient" loading={saving} onClick={savePrice}>{t("btn_save")}</Button>
          </div>
        </div>
      </Modal>

      {/* remove confirm */}
      <Modal isOpen={removing !== null} onClose={() => setRemoving(null)}>
        <div className="space-y-4 p-6">
          <h2 className="text-lg font-bold text-red-600">{t("remove_title")}</h2>
          <p className="text-sm text-muted-foreground">{t("remove_msg", { name: removing?.name ?? "" })}</p>
          <div className="flex justify-end gap-2 pt-2">
            <Button variant="outline" onClick={() => setRemoving(null)}>{t("btn_cancel")}</Button>
            <Button variant="destructive" loading={removeBusy} onClick={confirmRemove}>{t("btn_remove_confirm")}</Button>
          </div>
        </div>
      </Modal>

      <AddProductModal
        isOpen={addOpen}
        onClose={() => setAddOpen(false)}
        libraryId={libraryId}
        currency={lib?.currency ?? "EGP"}
        onAdded={() => { onChanged(); void reload(); }}
      />

      <ImportWizardModal
        isOpen={importOpen}
        onClose={() => setImportOpen(false)}
        libraryId={libraryId}
        onDone={() => { onChanged(); void reload(); }}
      />
    </div>
  );
}

// ---------------------------------------------------------------------------
// Changes tab — the release log; Phase 2 renders the same rows as the
// pharmacy «الفرق منذ آخر مزامنة» diff screen.
// ---------------------------------------------------------------------------

function ChangesTab({ libraryId }: { libraryId: string }) {
  const t = useT("libraries");
  const [items, setItems] = useState<LibraryChangeRow[]>([]);
  const [pagination, setPagination] = useState({ total: 0, page: 1, page_size: 20, total_pages: 1 });
  const [page, setPage] = useState(1);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let alive = true;
    (async () => {
      setLoading(true);
      try {
        const res = await librariesApi.changes(libraryId, page);
        if (!alive) return;
        setItems(res.items);
        setPagination(res.pagination);
      } catch (e) {
        if (alive) toast.error(e instanceof ApiError && e.message ? e.message : t("error_load"));
      } finally {
        if (alive) setLoading(false);
      }
    })();
    return () => { alive = false; };
  }, [libraryId, page, t]);

  const typeBadge = (ct: LibraryChangeRow["change_type"]) => {
    switch (ct) {
      case "added": return <Badge className="bg-emerald-100 text-emerald-700 dark:bg-emerald-900/40 dark:text-emerald-300">{t("chg_added")}</Badge>;
      case "price_changed": return <Badge className="bg-amber-100 text-amber-700 dark:bg-amber-900/40 dark:text-amber-300">{t("chg_price")}</Badge>;
      case "metadata_changed": return <Badge className="bg-blue-100 text-blue-700 dark:bg-blue-900/40 dark:text-blue-300">{t("chg_metadata")}</Badge>;
      case "removed": return <Badge className="bg-red-100 text-red-700 dark:bg-red-900/40 dark:text-red-300">{t("chg_removed")}</Badge>;
      default: return null;
    }
  };

  return (
    <div className="space-y-4">
      <Card>
        <CardContent className="p-0">
          {loading ? (
            <p className="p-6 text-sm text-muted-foreground">{t("loading")}</p>
          ) : items.length === 0 ? (
            <p className="p-10 text-center text-sm text-muted-foreground">{t("empty_changes")}</p>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>{t("col_version")}</TableHead>
                  <TableHead>{t("col_type")}</TableHead>
                  <TableHead>{t("col_product")}</TableHead>
                  <TableHead>{t("col_price_delta")}</TableHead>
                  <TableHead>{t("col_when")}</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {items.map((c) => (
                  <TableRow key={c.id}>
                    <TableCell>{t("version_short", { v: c.version })}</TableCell>
                    <TableCell>{typeBadge(c.change_type)}</TableCell>
                    <TableCell>
                      <div className="font-medium">{c.product_name}</div>
                      {c.summary ? <div className="text-xs text-muted-foreground">{c.summary}</div> : null}
                    </TableCell>
                    <TableCell dir="ltr" className="text-sm">
                      {c.change_type === "price_changed" && c.old_price_piastres !== null && c.new_price_piastres !== null ? (
                        <span>
                          <span className="text-muted-foreground line-through">{money(c.old_price_piastres)}</span>
                          {" → "}
                          <span className="font-semibold">{money(c.new_price_piastres)}</span>
                        </span>
                      ) : c.change_type === "added" && c.new_price_piastres !== null ? (
                        <span className="font-semibold">{money(c.new_price_piastres)}</span>
                      ) : (
                        "—"
                      )}
                    </TableCell>
                    <TableCell className="text-xs text-muted-foreground">{fmtDate(c.created_at)}</TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
        </CardContent>
      </Card>

      {pagination.total_pages > 1 ? (
        <div className="flex items-center justify-between text-sm">
          <span className="text-muted-foreground">{t("pagination", { shown: items.length, total: fmtNumber(pagination.total) })}</span>
          <div className="flex gap-2">
            <Button variant="outline" size="sm" disabled={page <= 1} onClick={() => setPage((p) => p - 1)}>{t("btn_prev")}</Button>
            <Button variant="outline" size="sm" disabled={page >= pagination.total_pages} onClick={() => setPage((p) => p + 1)}>{t("btn_next")}</Button>
          </div>
        </div>
      ) : null}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Settings tab — metadata + danger zone
// ---------------------------------------------------------------------------

function SettingsTab({ lib, onSaved, onDeleted }: { lib: LibraryRow | null; onSaved: () => void; onDeleted: () => void }) {
  const t = useT("libraries");
  const [name, setName] = useState("");
  const [description, setDescription] = useState("");
  const [country, setCountry] = useState("");
  const [currency, setCurrency] = useState("EGP");
  const [saving, setSaving] = useState(false);
  const [confirmDelete, setConfirmDelete] = useState(false);
  const [deleteBusy, setDeleteBusy] = useState(false);

  useEffect(() => {
    if (lib) {
      setName(lib.name);
      setDescription(lib.description ?? "");
      setCountry(lib.country_code ?? "");
      setCurrency(lib.currency);
    }
  }, [lib]);

  if (!lib) return <p className="text-sm text-muted-foreground">{t("loading")}</p>;

  const save = async () => {
    if (!name.trim()) {
      toast.error(t("err_name_required"));
      return;
    }
    setSaving(true);
    try {
      await librariesApi.update(lib.id, { name, description, country_code: country, currency });
      toast.success(t("ok_updated"));
      onSaved();
    } catch (e) {
      toast.error(e instanceof ApiError && e.message ? e.message : t("error_save"));
    } finally {
      setSaving(false);
    }
  };

  const doDelete = async () => {
    setDeleteBusy(true);
    try {
      await librariesApi.remove(lib.id);
      toast.success(t("ok_deleted"));
      onDeleted();
    } catch (e) {
      toast.error(e instanceof ApiError && e.message ? e.message : t("error_delete"));
      setDeleteBusy(false);
    }
  };

  return (
    <div className="space-y-6 max-w-2xl">
      <Card>
        <CardContent className="pt-6 space-y-4">
          <h2 className="font-semibold">{t("settings_general")}</h2>
          <div className="space-y-1.5">
            <label className="text-sm font-medium">{t("fld_name")}</label>
            <Input value={name} onChange={(e) => setName(e.target.value)} />
          </div>
          <div className="space-y-1.5">
            <label className="text-sm font-medium">{t("fld_description")}</label>
            <Input value={description} onChange={(e) => setDescription(e.target.value)} />
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1.5">
              <label className="text-sm font-medium">{t("fld_country")}</label>
              <select className="w-full h-9 rounded-md border border-input bg-transparent px-3 text-sm" value={country} onChange={(e) => setCountry(e.target.value)}>
                <option value="">{t("country_global")}</option>
                {COUNTRY_OPTIONS.map((c) => (<option key={c} value={c}>{c}</option>))}
              </select>
            </div>
            <div className="space-y-1.5">
              <label className="text-sm font-medium">{t("fld_currency")}</label>
              <select className="w-full h-9 rounded-md border border-input bg-transparent px-3 text-sm" value={currency} onChange={(e) => setCurrency(e.target.value)}>
                {CURRENCY_OPTIONS.map((c) => (<option key={c} value={c}>{c}</option>))}
              </select>
            </div>
          </div>
          <div className="flex justify-end">
            <Button variant="gradient" loading={saving} onClick={save}>{t("btn_save")}</Button>
          </div>
        </CardContent>
      </Card>

      <Card className="border-red-200 dark:border-red-900/50">
        <CardContent className="pt-6 space-y-3">
          <h2 className="font-semibold text-red-600">{t("settings_danger")}</h2>
          <p className="text-sm text-muted-foreground">{t("settings_danger_msg")}</p>
          {lib.synced_pharmacies > 0 ? (
            <p className="text-sm text-amber-600 bg-amber-50 dark:bg-amber-900/20 rounded-md p-3">
              {t("delete_warn_synced", { n: fmtNumber(lib.synced_pharmacies) })}
            </p>
          ) : null}
          <Button variant="destructive" onClick={() => setConfirmDelete(true)}>
            <Trash2 className="h-4 w-4" />{t("btn_delete")}
          </Button>
        </CardContent>
      </Card>

      <Modal isOpen={confirmDelete} onClose={() => setConfirmDelete(false)}>
        <div className="space-y-4 p-6">
          <h2 className="text-lg font-bold text-red-600">{t("delete_title")}</h2>
          <p className="text-sm text-muted-foreground">{t("delete_msg", { name: lib.name })}</p>
          <div className="flex justify-end gap-2 pt-2">
            <Button variant="outline" onClick={() => setConfirmDelete(false)}>{t("btn_cancel")}</Button>
            <Button variant="destructive" loading={deleteBusy} onClick={doDelete}>{t("btn_delete_confirm")}</Button>
          </div>
        </div>
      </Modal>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Add product modal — pick an existing catalog product OR create a verified
// one inline. Both paths converge on the upsert endpoint: re-adding an
// entry with a different price updates it and logs price_changed.
// ---------------------------------------------------------------------------

type NewProductForm = {
  name: string; generic_name: string; dosage_form: string; strength: string;
  product_category: string; requires_prescription: string; barcode: string;
  generate_barcode: boolean; manufacturer_name: string;
};

const emptyNewProduct = (): NewProductForm => ({
  name: "", generic_name: "", dosage_form: "tablet", strength: "",
  product_category: "medication", requires_prescription: "no", barcode: "",
  generate_barcode: false, manufacturer_name: "",
});

function AddProductModal({ isOpen, onClose, libraryId, currency, onAdded }: {
  isOpen: boolean; onClose: () => void; libraryId: string; currency: string; onAdded: () => void;
}) {
  const t = useT("libraries");
  const [mode, setMode] = useState<"catalog" | "new">("catalog");
  const [search, setSearch] = useState("");
  const [results, setResults] = useState<CatalogProductRow[]>([]);
  const [searching, setSearching] = useState(false);
  const [selected, setSelected] = useState<CatalogProductRow | null>(null);
  const [price, setPrice] = useState("");
  const [form, setForm] = useState<NewProductForm>(emptyNewProduct());
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    if (!isOpen) {
      setSearch(""); setResults([]); setSelected(null); setPrice(""); setForm(emptyNewProduct());
      setMode("catalog");
    }
  }, [isOpen]);

  useEffect(() => {
    if (!isOpen || mode !== "catalog") return;
    let alive = true;
    const timer = setTimeout(async () => {
      setSearching(true);
      try {
        const res = await librariesApi.catalogProducts(search, 1, 25);
        if (!alive) return;
        setResults(res.items);
      } catch {
        /* search is best-effort; the toast fires on submit failures */
      } finally {
        if (alive) setSearching(false);
      }
    }, 300);
    return () => { alive = false; clearTimeout(timer); };
  }, [isOpen, mode, search]);

  const submit = async () => {
    const piastres = price.trim() === "" ? null : Math.round(parseFloat(price.replace(",", ".")) * 100);
    if (piastres !== null && (isNaN(piastres) || piastres < 0)) {
      toast.error(t("err_invalid_price"));
      return;
    }
    setSaving(true);
    try {
      const payload = mode === "catalog"
        ? { global_product_id: selected?.id, official_price_piastres: piastres ?? undefined }
        : { new_product: { ...form, generate_barcode: form.generate_barcode || !form.barcode }, official_price_piastres: piastres ?? undefined };
      if (mode === "catalog" && !selected) {
        toast.error(t("err_pick_product"));
        return;
      }
      if (mode === "new" && !form.name.trim()) {
        toast.error(t("err_name_required_product"));
        return;
      }
      const res = await librariesApi.addProduct(libraryId, payload);
      toast.success(res.action === "added" ? t("ok_product_added") : t("ok_price_updated"));
      onAdded();
      onClose();
    } catch (e) {
      toast.error(e instanceof ApiError && e.message ? e.message : t("error_save"));
    } finally {
      setSaving(false);
    }
  };

  return (
    <Modal isOpen={isOpen} onClose={onClose}>
      <div className="space-y-4 p-6 max-w-2xl">
        <h2 className="text-lg font-bold">{t("add_title")}</h2>
        <div className="flex gap-2">
          <Button variant={mode === "catalog" ? "default" : "outline"} size="sm" onClick={() => setMode("catalog")}>
            {t("mode_catalog")}
          </Button>
          <Button variant={mode === "new" ? "default" : "outline"} size="sm" onClick={() => setMode("new")}>
            {t("mode_new")}
          </Button>
        </div>

        {mode === "catalog" ? (
          <div className="space-y-3">
            <Input placeholder={t("ph_search_catalog")} value={search} onChange={(e) => setSearch(e.target.value)} />
            <div className="max-h-64 overflow-y-auto rounded-md border divide-y">
              {searching && results.length === 0 ? (
                <p className="p-4 text-sm text-muted-foreground">{t("loading")}</p>
              ) : results.length === 0 ? (
                <p className="p-4 text-sm text-muted-foreground">{t("empty_catalog")}</p>
              ) : (
                results.map((r) => {
                  const inThisLib = r.libraries.some((l) => l.id === libraryId);
                  return (
                    <button
                      key={r.id}
                      className={`w-full text-start px-3 py-2.5 hover:bg-muted/50 transition-colors ${selected?.id === r.id ? "bg-emerald-50 dark:bg-emerald-900/20" : ""}`}
                      onClick={() => setSelected(r)}
                    >
                      <div className="flex items-center justify-between gap-2">
                        <span className="text-sm font-medium flex items-center gap-1.5">
                          {r.name}
                          {r.is_verified ? <BadgeCheck className="h-3.5 w-3.5 text-emerald-600" /> : null}
                        </span>
                        <span dir="ltr" className="text-xs text-muted-foreground">{r.barcode ?? "—"}</span>
                      </div>
                      <div className="text-xs text-muted-foreground flex items-center gap-2">
                        <span>{[r.generic_name, r.strength].filter(Boolean).join(" · ")}</span>
                        {inThisLib ? <Badge variant="secondary">{t("in_this_library")}</Badge> : null}
                      </div>
                    </button>
                  );
                })
              )}
            </div>
          </div>
        ) : (
          <div className="space-y-3 max-h-72 overflow-y-auto pe-1">
            <div className="space-y-1.5">
              <label className="text-sm font-medium">{t("fld_product_name")}</label>
              <Input value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} />
            </div>
            <div className="grid grid-cols-2 gap-3">
              <div className="space-y-1.5">
                <label className="text-sm font-medium">{t("fld_generic_name")}</label>
                <Input value={form.generic_name} onChange={(e) => setForm({ ...form, generic_name: e.target.value })} />
              </div>
              <div className="space-y-1.5">
                <label className="text-sm font-medium">{t("fld_strength")}</label>
                <Input value={form.strength} onChange={(e) => setForm({ ...form, strength: e.target.value })} />
              </div>
            </div>
            <div className="grid grid-cols-2 gap-3">
              <div className="space-y-1.5">
                <label className="text-sm font-medium">{t("fld_dosage_form")}</label>
                <select className="w-full h-9 rounded-md border border-input bg-transparent px-3 text-sm" value={form.dosage_form} onChange={(e) => setForm({ ...form, dosage_form: e.target.value })}>
                  {DOSAGE_FORMS.map((d) => (<option key={d} value={d}>{t(`dosage_${d}`)}</option>))}
                </select>
              </div>
              <div className="space-y-1.5">
                <label className="text-sm font-medium">{t("fld_category")}</label>
                <select className="w-full h-9 rounded-md border border-input bg-transparent px-3 text-sm" value={form.product_category} onChange={(e) => setForm({ ...form, product_category: e.target.value })}>
                  {CATEGORIES.map((c) => (<option key={c} value={c}>{t(`category_${c}`)}</option>))}
                </select>
              </div>
            </div>
            <div className="space-y-1.5">
              <label className="text-sm font-medium">{t("fld_manufacturer")}</label>
              <Input value={form.manufacturer_name} onChange={(e) => setForm({ ...form, manufacturer_name: e.target.value })} />
            </div>
            <div className="space-y-1.5">
              <label className="text-sm font-medium">{t("fld_barcode")}</label>
              <div className="flex items-center gap-3">
                <Input dir="ltr" className="flex-1" value={form.barcode} onChange={(e) => setForm({ ...form, barcode: e.target.value })} placeholder={t("ph_barcode")} />
                <label className="flex items-center gap-1.5 text-xs whitespace-nowrap">
                  <input
                    type="checkbox"
                    checked={form.generate_barcode}
                    onChange={(e) => setForm({ ...form, generate_barcode: e.target.checked })}
                  />
                  {t("generate_barcode")}
                </label>
              </div>
            </div>
          </div>
        )}

        <div className="space-y-1.5">
          <label className="text-sm font-medium">{t("fld_official_price")} ({currency})</label>
          <Input dir="ltr" inputMode="decimal" value={price} onChange={(e) => setPrice(e.target.value)} placeholder={t("ph_price")} />
          <p className="text-xs text-muted-foreground">{t("hint_price_change")}</p>
        </div>

        <div className="flex justify-end gap-2 pt-2">
          <Button variant="outline" onClick={onClose}>{t("btn_cancel")}</Button>
          <Button variant="gradient" loading={saving} onClick={submit}>{t("btn_add")}</Button>
        </div>
      </div>
    </Modal>
  );
}

// ---------------------------------------------------------------------------
// Import wizard — upload → mapping preview → execute report. Mirrors the
// pharmacy Excel import UX so the admin already knows the flow.
// ---------------------------------------------------------------------------

const FIELD_LABEL_KEYS: Record<string, string> = {
  name: "imp_field_name",
  barcode: "imp_field_barcode",
  selling_price: "imp_field_selling_price",
  generic_name: "imp_field_generic_name",
  strength: "imp_field_strength",
  dosage_form: "imp_field_dosage_form",
  manufacturer: "imp_field_manufacturer",
};

function ImportWizardModal({ isOpen, onClose, libraryId, onDone }: {
  isOpen: boolean; onClose: () => void; libraryId: string; onDone: () => void;
}) {
  const t = useT("libraries");
  const [file, setFile] = useState<File | null>(null);
  const [preview, setPreview] = useState<LibraryImportPreview | null>(null);
  const [mapping, setMapping] = useState<Record<string, number>>({});
  const [report, setReport] = useState<LibraryImportReport | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");

  const reset = () => {
    setFile(null); setPreview(null); setReport(null); setMapping({}); setError("");
  };

  useEffect(() => {
    if (!isOpen) reset();
  }, [isOpen]);

  const upload = async (f: File) => {
    setFile(f);
    setError("");
    setBusy(true);
    try {
      const pv = await librariesApi.importPreview(libraryId, f);
      setPreview(pv);
      setMapping(pv.mapping);
    } catch (e) {
      setError(e instanceof ApiError && e.message ? e.message : t("error_preview"));
    } finally {
      setBusy(false);
    }
  };

  const execute = async () => {
    if (!file) return;
    setBusy(true);
    setError("");
    try {
      const rep = await librariesApi.importExecute(libraryId, file, mapping);
      setReport(rep);
      onDone();
    } catch (e) {
      setError(e instanceof ApiError && e.message ? e.message : t("error_execute"));
    } finally {
      setBusy(false);
    }
  };

  return (
    <Modal isOpen={isOpen} onClose={onClose}>
      <div className="space-y-4 p-6 max-w-2xl">
        <h2 className="text-lg font-bold">{t("imp_title")}</h2>
        <p className="text-sm text-muted-foreground">{t("imp_subtitle")}</p>

        {!preview && !report ? (
          <div className="space-y-3">
            <label
              className="flex flex-col items-center justify-center gap-2 border-2 border-dashed rounded-lg p-8 cursor-pointer hover:border-emerald-500 transition-colors"
              data-testid="library-import-file-input"
            >
              <Upload className="h-8 w-8 text-muted-foreground" />
              <span className="text-sm">{file ? file.name : t("imp_drop")}</span>
              <span className="text-xs text-muted-foreground">{t("imp_formats")}</span>
              <input
                type="file"
                className="hidden"
                accept=".xlsx,.csv,.txt"
                onChange={(e) => { const f = e.target.files?.[0]; if (f) void upload(f); }}
              />
            </label>
            {busy ? <p className="text-sm text-muted-foreground">{t("loading")}</p> : null}
          </div>
        ) : null}

        {preview && !report ? (
          <div className="space-y-4">
            <div className="flex flex-wrap gap-2 text-sm">
              <Badge variant="outline">{t("imp_rows", { n: fmtNumber(preview.total_rows) })}</Badge>
              <Badge className="bg-emerald-100 text-emerald-700 dark:bg-emerald-900/40 dark:text-emerald-300">
                {t("imp_valid", { n: fmtNumber(preview.valid_rows) })}
              </Badge>
              {preview.invalid_rows > 0 ? (
                <Badge className="bg-red-100 text-red-700 dark:bg-red-900/40 dark:text-red-300">
                  {t("imp_invalid", { n: fmtNumber(preview.invalid_rows) })}
                </Badge>
              ) : null}
            </div>

            {preview.invalid_reasons.length > 0 ? (
              <div className="text-xs text-red-600 bg-red-50 dark:bg-red-900/20 rounded-md p-3 space-y-1">
                {preview.invalid_reasons.map((r, i) => (<p key={i}>{r}</p>))}
              </div>
            ) : null}

            <div className="space-y-2">
              <p className="text-sm font-medium">{t("imp_mapping")}</p>
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-2">
                {preview.fields.filter((f) => f in FIELD_LABEL_KEYS).map((f) => (
                  <div key={f} className="flex items-center gap-2 justify-between">
                    <span className="text-xs font-medium">{t(FIELD_LABEL_KEYS[f])}</span>
                    <select
                      className="h-8 rounded-md border border-input bg-transparent px-2 text-xs max-w-[55%]"
                      value={String(mapping[f] ?? -1)}
                      onChange={(e) => setMapping({ ...mapping, [f]: parseInt(e.target.value, 10) })}
                    >
                      <option value="-1">{t("imp_ignore")}</option>
                      {preview.headers.map((h, i) => (
                        <option key={i} value={String(i)}>{h}</option>
                      ))}
                    </select>
                  </div>
                ))}
              </div>
            </div>

            {preview.sample.length > 0 ? (
              <div className="overflow-x-auto rounded-md border">
                <Table>
                  <TableHeader>
                    <TableRow>
                      {["name", "barcode", "price", "generic_name", "strength"].map((k) => (
                        <TableHead key={k}>{t(`imp_col_${k}`)}</TableHead>
                      ))}
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {preview.sample.slice(0, 8).map((row, i) => (
                      <TableRow key={i}>
                        <TableCell className="text-xs">{row.name}</TableCell>
                        <TableCell className="text-xs" dir="ltr">{row.barcode}</TableCell>
                        <TableCell className="text-xs" dir="ltr">{row.price}</TableCell>
                        <TableCell className="text-xs">{row.generic_name}</TableCell>
                        <TableCell className="text-xs">{row.strength}</TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              </div>
            ) : null}

            <div className="flex justify-end gap-2 pt-2">
              <Button variant="outline" onClick={reset}>{t("imp_back")}</Button>
              <Button variant="gradient" loading={busy} disabled={preview.valid_rows === 0} onClick={execute}>
                {t("imp_execute", { n: fmtNumber(preview.valid_rows) })}
              </Button>
            </div>
          </div>
        ) : null}

        {report ? (
          <div className="space-y-4">
            <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
              <Card><CardContent className="pt-4 text-center">
                <p className="text-2xl font-bold text-emerald-600">{fmtNumber(report.added)}</p>
                <p className="text-xs text-muted-foreground">{t("rep_added")}</p>
              </CardContent></Card>
              <Card><CardContent className="pt-4 text-center">
                <p className="text-2xl font-bold text-amber-600">{fmtNumber(report.price_updated)}</p>
                <p className="text-xs text-muted-foreground">{t("rep_price_updated")}</p>
              </CardContent></Card>
              <Card><CardContent className="pt-4 text-center">
                <p className="text-2xl font-bold">{fmtNumber(report.products_created)}</p>
                <p className="text-xs text-muted-foreground">{t("rep_created")}</p>
              </CardContent></Card>
              <Card><CardContent className="pt-4 text-center">
                <p className="text-2xl font-bold text-muted-foreground">{fmtNumber(report.unchanged)}</p>
                <p className="text-xs text-muted-foreground">{t("rep_unchanged")}</p>
              </CardContent></Card>
            </div>
            {report.failed > 0 ? (
              <p className="text-sm text-red-600">{t("rep_failed", { n: fmtNumber(report.failed) })}</p>
            ) : null}
            {report.errors.length > 0 ? (
              <div className="text-xs text-red-600 bg-red-50 dark:bg-red-900/20 rounded-md p-3 space-y-1 max-h-32 overflow-y-auto">
                {report.errors.map((r, i) => (<p key={i}>{r}</p>))}
              </div>
            ) : null}
            <div className="flex justify-end">
              <Button variant="gradient" onClick={onClose}>{t("imp_done")}</Button>
            </div>
          </div>
        ) : null}

        {error ? <p className="text-sm text-red-600">{error}</p> : null}
      </div>
    </Modal>
  );
}
