import { redirect } from 'next/navigation'

/** الجذر في تطبيق نقطة البيع = شاشة البيع مباشرة */
export default function Home() {
  redirect('/pos')
}
