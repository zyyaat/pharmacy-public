import PharmacyAppLink from '@/components/pharmacy-app-link'

const features = [
  {
    index: '01',
    title: 'كل ما تحتاجه في مكان واحد',
    copy: 'المخزون، الموظفون، الفروع والتقارير في مساحة تشغيل واحدة وواضحة.',
  },
  {
    index: '02',
    title: 'قرارات أسرع كل يوم',
    copy: 'بيانات مباشرة تساعدك على معرفة ما يحتاج إلى انتباهك قبل أن يتحول إلى مشكلة.',
  },
  {
    index: '03',
    title: 'مصمم لينمو معك',
    copy: 'ابدأ بصيدلية واحدة، ثم وسّع إدارتك للفروع بدون تغيير طريقة عملك.',
  },
]

export default function Home() {
  return (
    <main className="marketing-shell" dir="rtl">
      <div className="ambient ambient-one" />
      <div className="ambient ambient-two" />

      <header className="site-header">
        <a className="brand" href="#top" aria-label="Pharmacy OS - الرئيسية">
          <img
            className="brand-logo"
            src="/brand/pharmacy-os-logo.svg"
            alt="Pharmacy OS"
            width="260"
            height="64"
          />
        </a>

        <nav className="main-nav" aria-label="التنقل الرئيسي">
          <a className="active" href="#top">الرئيسية</a>
          <a href="#features">المزايا</a>
          <a href="#story">كيف تعمل</a>
          <a href="#contact">تواصل معنا</a>
        </nav>

        <a className="theme-button" href="#features" aria-label="استكشف المنصة">
          <span aria-hidden="true">◐</span>
        </a>
      </header>

      <section className="hero" id="top">
        <div className="hero-content">
          <div className="availability">
            <span className="pulse-dot" />
            متاح للصيدليات الحديثة
          </div>

          <p className="eyebrow">منصة تشغيل الصيدلية</p>
          <h1>
            صيدليتك
            <span>بإدارة أذكى</span>
          </h1>
          <p className="hero-copy">
            كل ما تحتاجه لتدير يومك بثقة، من أول علبة دواء إلى آخر تقرير.
            <br />
            بساطة في التشغيل، ووضوح في كل قرار.
          </p>

          <div className="hero-actions" id="start">
            <PharmacyAppLink className="button button-primary">
              ابدأ الآن
              <span aria-hidden="true">←</span>
            </PharmacyAppLink>
            <a className="button button-ghost" href="#features">
              اكتشف المنصة
              <span aria-hidden="true">↓</span>
            </a>
          </div>

          <div className="social-row" aria-label="روابط التواصل">
            <a href="#contact" aria-label="البريد الإلكتروني">
              <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 5h16v14H4zM4 6l8 6 8-6" /></svg>
            </a>
            <a href="#contact" aria-label="تواصل معنا">
              <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M6 3h12v18H6zM9 7h6M9 11h6M9 15h3" /></svg>
            </a>
            <a href="#features" aria-label="استكشف المزايا">
              <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 3v18M3 12h18M5.5 5.5l13 13M18.5 5.5l-13 13" /></svg>
            </a>
          </div>
        </div>

        <div className="hero-art" aria-hidden="true">
          <div className="art-halo" />
          <div className="art-grid" />
          <div className="pharmacy-illustration">
            <div className="illustration-top">
              <span className="cross cross-one" />
              <span className="cross cross-two" />
            </div>
            <div className="bottle bottle-large"><span className="bottle-label">P</span></div>
            <div className="bottle bottle-small"><span className="bottle-label">+</span></div>
            <div className="capsule capsule-one" />
            <div className="capsule capsule-two" />
            <div className="illustration-line line-one" />
            <div className="illustration-line line-two" />
          </div>
          <div className="art-caption">
            <span>PHARMACY</span>
            <span>OPERATING SYSTEM</span>
          </div>
        </div>

        <div className="scroll-cue">
          <span>مرر لاكتشاف المزيد</span>
          <i />
        </div>
      </section>

      <section className="feature-strip" id="features">
        <div className="section-intro">
          <span className="section-number">01 / 03</span>
          <h2>وضوح أكثر.<br /><em>تشغيل أسهل.</em></h2>
        </div>
        <div className="feature-list">
          {features.map((feature) => (
            <article className="feature-item" key={feature.index}>
              <span>{feature.index}</span>
              <div>
                <h3>{feature.title}</h3>
                <p>{feature.copy}</p>
              </div>
            </article>
          ))}
        </div>
      </section>

      <section className="story-section" id="story">
        <div>
          <span className="section-number">02 / 03</span>
          <p className="eyebrow">طريقة مختلفة للإدارة</p>
          <h2>أنت تهتم<br /><em>بصيدليتك.</em></h2>
        </div>
        <p className="story-copy">
          نحن نهتم بأن تكون الأدوات التي تستخدمها على قدر هذا الاهتمام.
          Pharmacy OS يمنحك صورة كاملة عن عملك، حتى تبقى قريبًا من مرضاك
          وبعيدًا عن الفوضى اليومية.
        </p>
      </section>

      <section className="contact-section" id="contact">
        <div>
          <span className="section-number">03 / 03</span>
          <p className="eyebrow">جاهز للخطوة التالية؟</p>
          <h2>خلّ إدارة<br /><em>صيدليتك أسهل.</em></h2>
        </div>
        <a className="button button-primary contact-button" href="mailto:hello@pharmacy.os">
          تواصل مع فريقنا
          <span aria-hidden="true">←</span>
        </a>
      </section>

      <footer className="site-footer">
        <span>© 2026 Pharmacy OS</span>
        <span>بُني للصيدليات التي تريد أن تنمو</span>
        <a href="#top">العودة للأعلى ↑</a>
      </footer>
    </main>
  )
}
