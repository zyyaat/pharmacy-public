// مكتبات المنتجات المركزية — طبقة الواجهة لجهة الصيدلية (المرحلة 2).
//
// كل المبالغ قروش صحيحة (piastres) وتُعرض عبر formatPiastres فقط، وكل
// النصوص المرئية تمر عبر مساحة الترجمة 'libraries'.

import { apiFetch } from './api'

export interface PharmacyLibrary {
  id: string
  name: string
  description: string
  country_code: string
  currency: string
  version: number
  published_at: string | null
  last_synced_version: number
  synced_at: string | null
  versions_behind: number
  sync_status: 'not_imported' | 'up_to_date' | 'update_available'
  pending_changes: number
  product_count: number
}

export interface LibraryProductRow {
  global_product_id: string
  name: string
  generic_name: string
  brand_name: string
  barcode: string
  strength: string
  dosage_form: string
  is_verified: boolean
  official_price_piastres: number
  pharmacy_product_id: string | null
  my_price_piastres: number | null
  already_have: boolean
}

export interface LibraryMatchCandidate {
  pharmacy_product_id: string
  name: string
  barcode: string
  selling_price_piastres: number
  score: number
  match_type: 'global_match' | 'barcode' | 'name' | 'name_contains'
}

export interface ImportCandidate {
  global_product_id: string
  name: string
  barcode: string
  official_price_piastres: number
  already_have: boolean
  pharmacy_product_id?: string
  my_price_piastres?: number | null
  suggested_action: 'create_new' | 'link_existing' | 'already_have' | 'plan_limited'
  matches?: LibraryMatchCandidate[]
  plan_limited?: boolean
}

export interface ImportPreview {
  candidates: ImportCandidate[]
  summary: Record<string, number>
  plan: { products_used: number; products_limit: number }
}

export interface ImportExecuteResult {
  library_version: number
  applied: number
  products_created: number
  products_linked: number
  prices_updated: number
  skipped: Array<{ global_product_id: string; reason: string; product_name?: string }>
  plan: { products_used: number; products_limit: number }
}

export interface LibraryDiffChange {
  global_product_id: string
  product_name: string
  barcode: string
  version: number
  change_type: 'added' | 'price_changed' | 'metadata_changed' | 'removed'
  old_price_piastres: number | null
  new_price_piastres: number | null
  summary: string
  created_at: string
}

export interface LibraryDiff {
  library: { id: string; name: string; version: number; last_synced_version: number; is_published: boolean }
  changes: LibraryDiffChange[]
  counts: Record<string, number>
}

export interface SyncResult {
  synced: boolean
  library_version: number
  last_synced_version: number
  nothing_to_do: boolean
  prices_updated: number
  products_added: number
  products_linked: number
  skipped: Array<{ global_product_id: string; reason: string; product_name?: string }>
  removed: Array<{ global_product_id: string; name: string }>
  plan: { products_used: number; products_limit: number }
}

export const librariesApi = {
  list() {
    return apiFetch<{ data: PharmacyLibrary[] }>('/pharmacy/libraries')
  },

  get(libraryId: string) {
    return apiFetch<{ data: PharmacyLibrary }>(`/pharmacy/libraries/${libraryId}`)
  },

  products(libraryId: string, search = '', page = 1, pageSize = 50) {
    const params = new URLSearchParams({ page: String(page), page_size: String(pageSize) })
    if (search) params.set('search', search)
    return apiFetch<{ data: LibraryProductRow[]; pagination: { total: number; page: number; page_size: number; total_pages: number } }>(
      `/pharmacy/libraries/${libraryId}/products?${params.toString()}`,
    )
  },

  diff(libraryId: string) {
    return apiFetch<{ data: LibraryDiff }>(`/pharmacy/libraries/${libraryId}/diff`)
  },

  importPreview(libraryId: string, mode: 'all' | 'selected', globalProductIds?: string[]) {
    return apiFetch<{ data: ImportPreview }>(`/pharmacy/libraries/${libraryId}/import/preview`, {
      method: 'POST',
      body: JSON.stringify(mode === 'selected' ? { mode, global_product_ids: globalProductIds } : { mode }),
    })
  },

  importExecute(libraryId: string, items: Array<{ global_product_id: string; action: 'create' | 'link'; pharmacy_product_id?: string }>) {
    return apiFetch<{ data: ImportExecuteResult }>(`/pharmacy/libraries/${libraryId}/import/execute`, {
      method: 'POST',
      body: JSON.stringify({ items }),
    })
  },

  sync(libraryId: string) {
    return apiFetch<{ data: SyncResult }>(`/pharmacy/libraries/${libraryId}/sync`, { method: 'POST' })
  },
}
