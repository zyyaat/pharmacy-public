// Task 48 — المترجم المركزي: بحث بمسار نقاط + استيفاء {params} + رجوع مرئي.
// الرجوع المرئي (إظهار مسار المفتاح) مقصود: يجب ألا يصل أي مفتاح ناقص
// إلى الإنتاج بدون أن يلاحظه فحص validate_messages.py.
import type { Messages } from './messages'

export type TranslatorParams = Record<string, string | number>

export type Translator = (key: string, params?: TranslatorParams) => string

function lookup(messages: Messages, path: string): unknown {
  let current: unknown = messages
  for (const segment of path.split('.')) {
    if (current && typeof current === 'object' && segment in (current as Record<string, unknown>)) {
      current = (current as Record<string, unknown>)[segment]
    } else {
      return undefined
    }
  }
  return current
}

export function createTranslator(messages: Messages, namespace?: string): Translator {
  return (key, params) => {
    const path = namespace ? `${namespace}.${key}` : key
    const resolved = lookup(messages, path)
    let value = typeof resolved === 'string' ? resolved : path
    if (params) {
      for (const [name, raw] of Object.entries(params)) {
        value = value.replaceAll(`{${name}}`, String(raw))
      }
    }
    return value
  }
}
