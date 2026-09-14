"use client";

// Central product libraries («مكتبات المنتجات المركزية») — Phase 1 control
// room. The platform admin creates named, country-targeted libraries,
// feeds them from official price bulletins (Excel) or inline products, and
// publishes releases; pharmacies (Phase 2) import and pull updates. The
// official price NEVER lives on the product itself — it belongs to the
// library entry, so the same drug can carry different official prices per
// country/currency.

import React, { useCallback, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { Plus, Library as LibraryIcon, Globe2, Trash2, Pencil } from "lucide-react";
import { toast } from "sonner";
import { Card, CardContent, Button, Input, Badge } from "@/components/ui";
import { Table, TableHeader, TableBody, TableRow, TableHead, TableCell } from "@/components/ui/table";
import { Modal } from "@/components/ui/modal";
import { librariesApi, ApiError, type LibraryRow } from "@/lib/api";
import { useT } from "@/i18n/provider";
import { fmtNumber } from "@/i18n/format";

// Common country scopes the admin picks from; free text is allowed too.
const COUNTRY_OPTIONS = ["EG", "SA", "AE", "KW", "QA", "OM", "BH", "JO", "MA", "DZ", "TN", "LY", "SD"];
const CURRENCY_OPTIONS = ["EGP", "SAR", "AED", "KWD", "QAR", "OMR", "BHD", "JOD", "USD", "EUR"];

type EditorState = { id?: string; name: string; description: string; country: string; currency: string };

const emptyEditor = (): EditorState => ({ name: "", description: "", country: "", currency: "EGP" });

export default function LibrariesPage() {
  const t = useT("libraries");
  const router = useRouter();
  const [libraries, setLibraries] = useState<LibraryRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [editorOpen, setEditorOpen] = useState(false);
  const [saving, setSaving] = useState(false);
  const [editor, setEditor] = useState<EditorState>(emptyEditor());
  const [deleting, setDeleting] = useState<LibraryRow | null>(null);
  const [busy, setBusy] = useState(false);

  const reload = useCallback(async () => {
    setLoading(true);
    try {
      setLibraries(await librariesApi.list());
    } catch (e) {
      toast.error(e instanceof ApiError && e.message ? e.message : t("error_load"));
    } finally {
      setLoading(false);
    }
  }, [t]);

  useEffect(() => {
    void reload();
  }, [reload]);

  const openCreate = () => {
    setEditor(emptyEditor());
    setEditorOpen(true);
  };

  const openEdit = (lib: LibraryRow) => {
    setEditor({
      id: lib.id,
      name: lib.name,
      description: lib.description ?? "",
      country: lib.country_code ?? "",
      currency: lib.currency,
    });
    setEditorOpen(true);
  };

  const save = async () => {
    if (!editor.name.trim()) {
      toast.error(t("err_name_required"));
      return;
    }
    setSaving(true);
    try {
      if (editor.id) {
        await librariesApi.update(editor.id, {
          name: editor.name,
          description: editor.description,
          country_code: editor.country,
          currency: editor.currency,
        });
        toast.success(t("ok_updated"));
        setEditorOpen(false);
        await reload();
      } else {
        const created = await librariesApi.create({
          name: editor.name,
          description: editor.description,
          country_code: editor.country,
          currency: editor.currency,
        });
        toast.success(t("ok_created"));
        setEditorOpen(false);
        router.push(`/libraries/${created.id}`);
        return;
      }
    } catch (e) {
      toast.error(e instanceof ApiError && e.message ? e.message : t("error_save"));
    } finally {
      setSaving(false);
    }
  };

  const confirmDelete = async () => {
    if (!deleting) return;
    setBusy(true);
    try {
      await librariesApi.remove(deleting.id);
      toast.success(t("ok_deleted"));
      setDeleting(null);
      await reload();
    } catch (e) {
      toast.error(e instanceof ApiError && e.message ? e.message : t("error_delete"));
    } finally {
      setBusy(false);
    }
  };

  const totalProducts = libraries.reduce((s, l) => s + l.product_count, 0);
  const publishedCount = libraries.filter((l) => l.is_published).length;
  const draftCount = libraries.reduce((s, l) => s + l.draft_changes, 0);

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h1 className="text-2xl font-bold flex items-center gap-2">
            <LibraryIcon className="h-6 w-6 text-emerald-600" />
            {t("title")}
          </h1>
          <p className="text-sm text-muted-foreground mt-1">{t("subtitle")}</p>
        </div>
        <Button variant="gradient" onClick={openCreate}>
          <Plus className="h-4 w-4" />
          {t("btn_create")}
        </Button>
      </div>

      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
        <Card>
          <CardContent className="pt-6">
            <p className="text-sm text-muted-foreground">{t("kpi_libraries")}</p>
            <p className="text-3xl font-bold">{fmtNumber(libraries.length)}</p>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="pt-6">
            <p className="text-sm text-muted-foreground">{t("kpi_published")}</p>
            <p className="text-3xl font-bold text-emerald-600">{fmtNumber(publishedCount)}</p>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="pt-6">
            <p className="text-sm text-muted-foreground">{t("kpi_products")}</p>
            <p className="text-3xl font-bold">{fmtNumber(totalProducts)}</p>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="pt-6">
            <p className="text-sm text-muted-foreground">{t("kpi_draft_changes")}</p>
            <p className="text-3xl font-bold text-amber-600">{fmtNumber(draftCount)}</p>
          </CardContent>
        </Card>
      </div>

      <Card>
        <CardContent className="p-0">
          {loading ? (
            <p className="p-6 text-sm text-muted-foreground">{t("loading")}</p>
          ) : libraries.length === 0 ? (
            <div className="p-10 text-center space-y-2">
              <LibraryIcon className="h-10 w-10 mx-auto text-muted-foreground/40" />
              <p className="text-sm text-muted-foreground">{t("empty")}</p>
              <Button variant="outline" size="sm" onClick={openCreate}>
                <Plus className="h-4 w-4" />
                {t("btn_create")}
              </Button>
            </div>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>{t("col_name")}</TableHead>
                  <TableHead>{t("col_scope")}</TableHead>
                  <TableHead>{t("col_products")}</TableHead>
                  <TableHead>{t("col_version")}</TableHead>
                  <TableHead>{t("col_synced")}</TableHead>
                  <TableHead>{t("col_actions")}</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {libraries.map((lib) => (
                  <TableRow key={lib.id} className="cursor-pointer" onClick={() => router.push(`/libraries/${lib.id}`)}>
                    <TableCell>
                      <div className="font-medium">{lib.name}</div>
                      {lib.description ? (
                        <div className="text-xs text-muted-foreground line-clamp-1">{lib.description}</div>
                      ) : null}
                    </TableCell>
                    <TableCell>
                      <div className="flex flex-wrap items-center gap-1.5">
                        {lib.country_code ? (
                          <Badge variant="outline">{lib.country_code}</Badge>
                        ) : (
                          <Badge variant="outline" className="gap-1">
                            <Globe2 className="h-3 w-3" />
                            {t("badge_global")}
                          </Badge>
                        )}
                        <span className="text-xs text-muted-foreground">{lib.currency}</span>
                      </div>
                    </TableCell>
                    <TableCell>{fmtNumber(lib.product_count)}</TableCell>
                    <TableCell>
                      <div className="flex items-center gap-1.5 flex-wrap">
                        <span className="font-medium">{t("version_short", { v: lib.version })}</span>
                        {lib.is_published ? (
                          <Badge className="bg-emerald-100 text-emerald-700 dark:bg-emerald-900/40 dark:text-emerald-300">
                            {t("badge_published")}
                          </Badge>
                        ) : (
                          <Badge variant="secondary">{t("badge_draft")}</Badge>
                        )}
                        {lib.draft_changes > 0 ? (
                          <Badge variant="outline" className="text-amber-600 border-amber-300">
                            {t("badge_pending", { n: fmtNumber(lib.draft_changes) })}
                          </Badge>
                        ) : null}
                      </div>
                    </TableCell>
                    <TableCell>
                      {fmtNumber(lib.synced_pharmacies)}
                      {lib.synced_pharmacies > 0 ? (
                        <span className="text-xs text-muted-foreground"> {t("pharmacies_unit")}</span>
                      ) : null}
                    </TableCell>
                    <TableCell onClick={(e) => e.stopPropagation()}>
                      <div className="flex items-center gap-1">
                        <Button variant="ghost" size="sm" onClick={() => openEdit(lib)}>
                          <Pencil className="h-4 w-4" />
                          {t("btn_edit")}
                        </Button>
                        <Button
                          variant="ghost"
                          size="sm"
                          className="text-red-600 hover:text-red-700"
                          onClick={() => setDeleting(lib)}
                        >
                          <Trash2 className="h-4 w-4" />
                          {t("btn_delete")}
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

      <Modal isOpen={editorOpen} onClose={() => setEditorOpen(false)}>
        <div className="space-y-4 p-6">
          <h2 className="text-lg font-bold">{editor.id ? t("edit_title") : t("create_title")}</h2>
          <div className="space-y-1.5">
            <label className="text-sm font-medium">{t("fld_name")}</label>
            <Input value={editor.name} onChange={(e) => setEditor({ ...editor, name: e.target.value })} placeholder={t("ph_name")} />
          </div>
          <div className="space-y-1.5">
            <label className="text-sm font-medium">{t("fld_description")}</label>
            <Input value={editor.description} onChange={(e) => setEditor({ ...editor, description: e.target.value })} placeholder={t("ph_description")} />
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1.5">
              <label className="text-sm font-medium">{t("fld_country")}</label>
              <select
                className="w-full h-9 rounded-md border border-input bg-transparent px-3 text-sm"
                value={editor.country}
                onChange={(e) => setEditor({ ...editor, country: e.target.value })}
              >
                <option value="">{t("country_global")}</option>
                {COUNTRY_OPTIONS.map((c) => (
                  <option key={c} value={c}>{c}</option>
                ))}
              </select>
            </div>
            <div className="space-y-1.5">
              <label className="text-sm font-medium">{t("fld_currency")}</label>
              <select
                className="w-full h-9 rounded-md border border-input bg-transparent px-3 text-sm"
                value={editor.currency}
                onChange={(e) => setEditor({ ...editor, currency: e.target.value })}
              >
                {CURRENCY_OPTIONS.map((c) => (
                  <option key={c} value={c}>{c}</option>
                ))}
              </select>
            </div>
          </div>
          <p className="text-xs text-muted-foreground">{t("hint_scope")}</p>
          <div className="flex justify-end gap-2 pt-2">
            <Button variant="outline" onClick={() => setEditorOpen(false)}>{t("btn_cancel")}</Button>
            <Button variant="gradient" loading={saving} onClick={save}>{t("btn_save")}</Button>
          </div>
        </div>
      </Modal>

      <Modal isOpen={deleting !== null} onClose={() => setDeleting(null)}>
        <div className="space-y-4 p-6">
          <h2 className="text-lg font-bold text-red-600">{t("delete_title")}</h2>
          <p className="text-sm text-muted-foreground">{t("delete_msg", { name: deleting?.name ?? "" })}</p>
          {deleting && deleting.synced_pharmacies > 0 ? (
            <p className="text-sm text-amber-600 bg-amber-50 dark:bg-amber-900/20 rounded-md p-3">
              {t("delete_warn_synced", { n: fmtNumber(deleting.synced_pharmacies) })}
            </p>
          ) : null}
          <div className="flex justify-end gap-2 pt-2">
            <Button variant="outline" onClick={() => setDeleting(null)}>{t("btn_cancel")}</Button>
            <Button variant="destructive" loading={busy} onClick={confirmDelete}>{t("btn_delete_confirm")}</Button>
          </div>
        </div>
      </Modal>
    </div>
  );
}
