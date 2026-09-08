import { redirect } from "next/navigation";

// Keep old bookmarks and links safe without pretending that a dedicated
// platform pharmacy API exists yet. The current account page is the source
// of truth for the platform's company/pharmacy account summary.
export default function PharmaciesRedirect() {
  redirect("/accounts");
}