#!/usr/bin/env python3
"""يولّد قواميس «libraries» ×8 لمطبيق الصيدلية + مفتاح nav في كل لغة.
يضمن تطابق مجموعة المفاتيح عبر اللغات (القاعدة العربية مرجع المفاتيح)."""
import json
import io
import os

BASE = "frontend/apps/pharmacy-app/src/i18n/messages"

TRANSLATIONS = {
    "en": {
        "title": "Product Libraries",
        "subtitle": "Ready-made libraries maintained by the platform team with official, always-updated prices — import what fits you and pull updates with one tap; your stock and costs are never touched.",
        "empty": "No libraries are available for your pharmacy yet — they will appear here once the admin publishes one for your country.",
        "error_load": "Could not load libraries",
        "error_sync": "Could not pull updates",
        "error_preview": "Could not prepare the preview",
        "error_execute": "Could not execute the import",
        "back": "Libraries",
        "products": "Products",
        "library_version": "Library version",
        "my_version": "My last sync",
        "browse": "Browse",
        "import": "Import",
        "import_more": "Import more",
        "pull_updates": "Pull updates",
        "update_available_hint": "A new update is available ({changes} changes) — latest version v{version}.",
        "not_imported_hint": "You have not imported from this library yet — importing adds products at their official prices with zero stock.",
        "status_not_imported": "Not imported",
        "status_up_to_date": "Up to date",
        "status_update_available": "Update available",
        "sync_result_title": "Pull result for «{name}»",
        "sync_nothing": "You are on the latest version — nothing new.",
        "sync_prices_updated": "Prices updated",
        "sync_products_added": "Products added",
        "sync_products_linked": "Products linked to twins",
        "sync_removed_count": "Products withdrawn from the library: {count}",
        "sync_removed_note": "What you already imported stays yours — withdrawal is informational only.",
        "sync_skipped_count": "Delayed items ({count}) — check the reason for each in the library details.",
        "tab_products": "Library products",
        "tab_updates": "Updates",
        "search_placeholder": "Search by name or barcode…",
        "no_products": "No matching products",
        "showing_of": "Showing {shown} of {total} products",
        "th_product": "Product",
        "th_barcode": "Barcode",
        "th_official_price": "Official price",
        "th_my_price": "My current price",
        "th_status": "Status",
        "have_it": "Already yours",
        "new_for_me": "New for you",
        "verified": "Verified product",
        "wizard_title": "Import from «{name}»",
        "wizard_subtitle": "Review the system's suggestion per product: add new, link to an existing one, or refresh the price — the final call is yours.",
        "summary_new": "New additions",
        "summary_suspects": "Possible twins",
        "summary_have": "Already yours",
        "summary_plan": "Beyond plan limit",
        "action_create": "Add as new",
        "action_link": "Link suggested",
        "action_have": "Already yours",
        "action_plan": "Beyond plan limit",
        "with_barcode": "Barcode {barcode}",
        "no_barcode": "No barcode",
        "official_price": "Official price {price}",
        "my_price": "My current price {price}",
        "possible_matches": "Existing products of yours that may be the same item:",
        "link_this": "Link",
        "decide_create": "Add as new",
        "decide_skip": "Skip",
        "plan_limited_note": "Beyond your plan's product limit — will not import",
        "wizard_redlines": "Fixed rules: stock and batches are never touched, your cost price stays yours, and the selling price follows the official one (you can still edit it locally later).",
        "wizard_execute": "Execute import ({count} items, {create} new)",
        "result_title": "Import completed",
        "result_prices": "Prices updated",
        "result_created": "New products",
        "result_linked": "Smart links",
        "result_skipped": "Skipped items: {count}",
        "result_version": "You are now on library version v{version}",
        "skip_plan_limit": "Beyond plan limit",
        "skip_no_official_price": "No official price",
        "skip_not_in_library": "Not in the library",
        "skip_link_target_invalid": "Invalid link target",
        "skip_link_conflict": "Link conflict",
        "diff_empty": "No new changes since your last sync — you are up to date.",
        "diff_never_synced": "Diffs will appear here after your first import.",
        "change_added": "Added",
        "change_price_changed": "Price change",
        "change_removed": "Withdrawn",
        "change_metadata_changed": "Data fix",
        "removed_note": "Products withdrawn from the library remain owned by your pharmacy with their stock — never auto-deleted.",
        "nav": "Product Libraries",
    },
    "fr": {
        "title": "Bibliothèques de produits",
        "subtitle": "Des bibliothèques prêtes gérées par l'équipe de la plateforme avec des prix officiels toujours à jour — importez ce qui vous convient et tirez les mises à jour en un clic ; votre stock et vos coûts ne sont jamais touchés.",
        "empty": "Aucune bibliothèque disponible pour votre pharmacie pour le moment — elle apparaîtra ici dès sa publication pour votre pays.",
        "error_load": "Impossible de charger les bibliothèques",
        "error_sync": "Impossible de tirer les mises à jour",
        "error_preview": "Impossible de préparer l'aperçu",
        "error_execute": "Impossible d'exécuter l'import",
        "back": "Bibliothèques",
        "products": "Produits",
        "library_version": "Version de la bibliothèque",
        "my_version": "Ma dernière synchro",
        "browse": "Parcourir",
        "import": "Importer",
        "import_more": "Importer plus",
        "pull_updates": "Tirer les mises à jour",
        "update_available_hint": "Une mise à jour est disponible ({changes} changements) — dernière version v{version}.",
        "not_imported_hint": "Vous n'avez encore rien importé de cette bibliothèque — l'import ajoute les produits à leurs prix officiels sans aucun stock.",
        "status_not_imported": "Non importée",
        "status_up_to_date": "À jour",
        "status_update_available": "Mise à jour disponible",
        "sync_result_title": "Résultat du tirage de «{name}»",
        "sync_nothing": "Vous êtes sur la dernière version — rien de nouveau.",
        "sync_prices_updated": "Prix mis à jour",
        "sync_products_added": "Produits ajoutés",
        "sync_products_linked": "Produits liés à leur jumeau",
        "sync_removed_count": "Produits retirés de la bibliothèque : {count}",
        "sync_removed_note": "Ce que vous avez déjà importé reste à vous — le retrait est purement informatif.",
        "sync_skipped_count": "Éléments reportés ({count}) — consultez la raison dans les détails de la bibliothèque.",
        "tab_products": "Produits de la bibliothèque",
        "tab_updates": "Mises à jour",
        "search_placeholder": "Rechercher par nom ou code-barres…",
        "no_products": "Aucun produit correspondant",
        "showing_of": "{shown} sur {total} produits affichés",
        "th_product": "Produit",
        "th_barcode": "Code-barres",
        "th_official_price": "Prix officiel",
        "th_my_price": "Mon prix actuel",
        "th_status": "Statut",
        "have_it": "Déjà à vous",
        "new_for_me": "Nouveau pour vous",
        "verified": "Produit vérifié",
        "wizard_title": "Importer depuis «{name}»",
        "wizard_subtitle": "Examinez la suggestion du système pour chaque produit : ajouter, lier à un existant ou actualiser le prix — la décision finale vous appartient.",
        "summary_new": "Nouvelles ajouts",
        "summary_suspects": "Jumeaux possibles",
        "summary_have": "Déjà à vous",
        "summary_plan": "Au-delà de la limite",
        "action_create": "Ajouter comme nouveau",
        "action_link": "Liaison suggérée",
        "action_have": "Déjà à vous",
        "action_plan": "Au-delà de la limite",
        "with_barcode": "Code-barres {barcode}",
        "no_barcode": "Sans code-barres",
        "official_price": "Prix officiel {price}",
        "my_price": "Mon prix actuel {price}",
        "possible_matches": "Vos produits existants qui pourraient être le même article :",
        "link_this": "Lier",
        "decide_create": "Ajouter comme nouveau",
        "decide_skip": "Ignorer",
        "plan_limited_note": "Au-delà de la limite de produits de votre offre — ne sera pas importé",
        "wizard_redlines": "Règles fixes : le stock et les lots ne sont jamais touchés, votre prix d'achat reste le vôtre et le prix de vente suit le prix officiel (modifiable localement ensuite).",
        "wizard_execute": "Exécuter l'import ({count} éléments, {create} nouveaux)",
        "result_title": "Import terminé",
        "result_prices": "Prix mis à jour",
        "result_created": "Nouveaux produits",
        "result_linked": "Liens intelligents",
        "result_skipped": "Éléments ignorés : {count}",
        "result_version": "Vous êtes maintenant sur la version v{version} de la bibliothèque",
        "skip_plan_limit": "Au-delà de la limite de l'offre",
        "skip_no_official_price": "Sans prix officiel",
        "skip_not_in_library": "Absent de la bibliothèque",
        "skip_link_target_invalid": "Cible de liaison invalide",
        "skip_link_conflict": "Conflit de liaison",
        "diff_empty": "Aucun changement depuis votre dernière synchro — vous êtes à jour.",
        "diff_never_synced": "Les différences apparaîtront ici après votre premier import.",
        "change_added": "Ajout",
        "change_price_changed": "Changement de prix",
        "change_removed": "Retiré",
        "change_metadata_changed": "Correction de données",
        "removed_note": "Les produits retirés de la bibliothèque restent la propriété de votre pharmacie avec leur stock — jamais supprimés automatiquement.",
        "nav": "Bibliothèques de produits",
    },
    "es": {
        "title": "Bibliotecas de productos",
        "subtitle": "Bibliotecas listas gestionadas por el equipo de la plataforma con precios oficiales siempre actualizados: importa lo que te convenga y descarga las actualizaciones con un toque; tu stock y tus costos nunca se tocan.",
        "empty": "Aún no hay bibliotecas disponibles para tu farmacia — aparecerán aquí cuando la administración publique una para tu país.",
        "error_load": "No se pudieron cargar las bibliotecas",
        "error_sync": "No se pudieron descargar las actualizaciones",
        "error_preview": "No se pudo preparar la vista previa",
        "error_execute": "No se pudo ejecutar la importación",
        "back": "Bibliotecas",
        "products": "Productos",
        "library_version": "Versión de la biblioteca",
        "my_version": "Mi última sincronización",
        "browse": "Explorar",
        "import": "Importar",
        "import_more": "Importar más",
        "pull_updates": "Descargar actualizaciones",
        "update_available_hint": "Hay una actualización disponible ({changes} cambios) — última versión v{version}.",
        "not_imported_hint": "Todavía no has importado de esta biblioteca — la importación añade productos a sus precios oficiales sin stock.",
        "status_not_imported": "No importada",
        "status_up_to_date": "Al día",
        "status_update_available": "Actualización disponible",
        "sync_result_title": "Resultado de la descarga de «{name}»",
        "sync_nothing": "Estás en la última versión — nada nuevo.",
        "sync_prices_updated": "Precios actualizados",
        "sync_products_added": "Productos añadidos",
        "sync_products_linked": "Productos vinculados a su gemelo",
        "sync_removed_count": "Productos retirados de la biblioteca: {count}",
        "sync_removed_note": "Lo que ya importaste sigue siendo tuyo — el retiro es solo informativo.",
        "sync_skipped_count": "Elementos pospuestos ({count}) — revisa el motivo en los detalles de la biblioteca.",
        "tab_products": "Productos de la biblioteca",
        "tab_updates": "Actualizaciones",
        "search_placeholder": "Buscar por nombre o código de barras…",
        "no_products": "Sin productos coincidentes",
        "showing_of": "Mostrando {shown} de {total} productos",
        "th_product": "Producto",
        "th_barcode": "Código de barras",
        "th_official_price": "Precio oficial",
        "th_my_price": "Mi precio actual",
        "th_status": "Estado",
        "have_it": "Ya lo tienes",
        "new_for_me": "Nuevo para ti",
        "verified": "Producto verificado",
        "wizard_title": "Importar desde «{name}»",
        "wizard_subtitle": "Revisa la sugerencia del sistema para cada producto: añadir nuevo, vincular a uno existente o actualizar el precio — la decisión final es tuya.",
        "summary_new": "Nuevas adiciones",
        "summary_suspects": "Gemelos posibles",
        "summary_have": "Ya los tienes",
        "summary_plan": "Más allá del límite",
        "action_create": "Añadir como nuevo",
        "action_link": "Vínculo sugerido",
        "action_have": "Ya lo tienes",
        "action_plan": "Más allá del límite",
        "with_barcode": "Código {barcode}",
        "no_barcode": "Sin código de barras",
        "official_price": "Precio oficial {price}",
        "my_price": "Mi precio actual {price}",
        "possible_matches": "Productos tuyos que podrían ser el mismo artículo:",
        "link_this": "Vincular",
        "decide_create": "Añadir como nuevo",
        "decide_skip": "Omitir",
        "plan_limited_note": "Supera el límite de productos de tu plan — no se importará",
        "wizard_redlines": "Reglas fijas: el stock y los lotes nunca se tocan, tu precio de compra sigue siendo tuyo y el precio de venta sigue el oficial (puedes editarlo localmente después).",
        "wizard_execute": "Ejecutar importación ({count} elementos, {create} nuevos)",
        "result_title": "Importación completada",
        "result_prices": "Precios actualizados",
        "result_created": "Productos nuevos",
        "result_linked": "Vínculos inteligentes",
        "result_skipped": "Elementos omitidos: {count}",
        "result_version": "Ahora estás en la versión v{version} de la biblioteca",
        "skip_plan_limit": "Supera el límite del plan",
        "skip_no_official_price": "Sin precio oficial",
        "skip_not_in_library": "No está en la biblioteca",
        "skip_link_target_invalid": "Objetivo de vínculo inválido",
        "skip_link_conflict": "Conflicto de vínculo",
        "diff_empty": "Sin cambios nuevos desde tu última sincronización — estás al día.",
        "diff_never_synced": "Las diferencias aparecerán aquí después de tu primera importación.",
        "change_added": "Añadido",
        "change_price_changed": "Cambio de precio",
        "change_removed": "Retirado",
        "change_metadata_changed": "Corrección de datos",
        "removed_note": "Los productos retirados de la biblioteca siguen siendo propiedad de tu farmacia con su stock — nunca se eliminan automáticamente.",
        "nav": "Bibliotecas de productos",
    },
}

# اللغات المتبقية: تُشتق من الإنجليزية مع تكييف العناوين (نفس استراتيجية
# القواميس الأخرى في التطبيق: العربية هي المرجع والبقية طبقة فوقها).
DERIVED = {
    "tr": {"nav": "Ürün Kütüphaneleri", "title": "Ürün Kütüphaneleri"},
    "zh": {"nav": "产品库", "title": "产品库"},
    "hi": {"nav": "उत्पाद लाइब्रेरी", "title": "उत्पाद लाइब्रेरी"},
    "ur": {"nav": "پروڈکٹ لائبریریاں", "title": "پروڈکٹ لائبریریاں"},
}


def main():
    ar = json.load(io.open(os.path.join(BASE, "ar", "libraries.json"), encoding="utf-8"))
    keys = list(ar.keys())
    written = []

    for locale, table in TRANSLATIONS.items():
        data = {}
        for key in keys:
            data[key] = table.get(key, ar[key])
        # مفتاح nav يُدار في nav.json — لا يُكتب داخل مساحة libraries
        data.pop("nav", None)
        assert set(data.keys()) == set(keys), locale
        path = os.path.join(BASE, locale, "libraries.json")
        io.open(path, "w", encoding="utf-8").write(
            json.dumps(data, ensure_ascii=False, indent=2) + "\n")
        written.append(path)

    for locale, override in DERIVED.items():
        data = {k: override.get(k, TRANSLATIONS["en"].get(k, ar[k])) for k in keys}
        data.pop("nav", None)
        path = os.path.join(BASE, locale, "libraries.json")
        io.open(path, "w", encoding="utf-8").write(
            json.dumps(data, ensure_ascii=False, indent=2) + "\n")
        written.append(path)

    # nav.json ×8 — إضافة مفتاح libraries بعد inventory
    nav_values = {
        "ar": "مكتبات المنتجات", "en": "Product Libraries",
        "fr": "Bibliothèques de produits", "es": "Bibliotecas de productos",
        "tr": "Ürün Kütüphaneleri", "zh": "产品库",
        "hi": "उत्पाद लाइब्रेरी", "ur": "پروڈکٹ لائبریریاں",
    }
    for locale, value in nav_values.items():
        path = os.path.join(BASE, locale, "nav.json")
        nav = json.load(io.open(path, encoding="utf-8"))
        if "libraries" not in nav:
            out = {}
            for k, v in nav.items():
                out[k] = v
                if k == "inventory":
                    out["libraries"] = value
            io.open(path, "w", encoding="utf-8").write(
                json.dumps(out, ensure_ascii=False, indent=2) + "\n")
        written.append(path)

    print(f"wrote {len(written)} files")
    # تحقق نهائي: تطابق مجموعة المفاتيح عبر اللغات
    for locale in ["ar", "en", "fr", "es", "tr", "zh", "hi", "ur"]:
        data = json.load(io.open(os.path.join(BASE, locale, "libraries.json"), encoding="utf-8"))
        assert set(data.keys()) == set(keys), f"key mismatch in {locale}"
    print("key-set verified consistent across 8 locales")


if __name__ == "__main__":
    main()
