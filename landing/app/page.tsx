import Plant from '@/components/Plant';
import Download from '@/components/Download';
import Growth from '@/components/Growth';

const faqs = [
  ['Is Pot free?', 'Yes. Pot is free, with no subscription, payments, or Pot account.'],
  ['Do I need to sign in again?', 'Pot reads compatible local usage logs. You keep signing in through Codex or Claude Code as usual. Pot does not ask for your password, API key, or authentication tokens.'],
  ['Does my plant need me every day?', 'No. A day off changes nothing. After a couple of days away it starts to look thirsty, after a week it turns yellow, and after two weeks it dries out. It never dies: about a week of work brings it back. Using more tokens helps up to a point, but growth has a daily limit.'],
  ['What kind of plant will I get?', 'Codex plants grow in a sage planter and Claude Code plants in terracotta. Beyond that, every seed is its own. You will find out as it grows.'],
  ['What does “Estimated API value” mean?', 'It estimates what supported token categories would be worth at documented public API reference prices for the model used. It is not your bill, your subscription cost, or the provider’s internal cost. Unknown models or incomplete usage are labeled unavailable or partial.'],
  ['What about multiple accounts?', 'Separate accounts can have separate plants when the local data identifies them. History without reliable account evidence stays in a clearly labeled local profile; Pot does not guess who owns it.'],
  ['Does anything leave my Mac?', 'The native garden and usage processing are local. Pot does not upload conversations, code, or usage statistics. Its once-a-day update check sends only Pot’s version number, and you can turn it off. This website uses cookieless Vercel Web Analytics to count visits and downloads by page, referrer, country and device type; it never identifies you.'],
  ['Which Macs and agents are supported?', 'Pot needs macOS 14 or later. It reads the local logs that the Codex app and CLI and Claude Code keep on your Mac, including compressed Codex archives. Cloud-only activity is not counted unless its logs are on your Mac.'],
];

export default function Home() {
  return <>
    <a className="skip-link" href="#main">Skip to content</a>
    <header className="site-header wrap">
      <a className="wordmark" href="#" aria-label="Pot home"><SproutIcon/>pot<span className="brand-period">.</span></a>
      <nav aria-label="Main navigation"><a href="#how-it-works">How it grows</a><a href="#your-garden">Your garden</a><a href="#privacy">Privacy</a></nav>
      <a className="nav-download" href="#download">Get Pot</a>
    </header>
    <main id="main">
      <section className="hero wrap" aria-labelledby="hero-title">
        <div className="hero-copy"><span className="eyebrow"><span className="tiny-sprout" aria-hidden="true">✳</span> A quiet companion for macOS</span>
          <h1 id="hero-title">A little plant<br/>on your <em>Mac.</em></h1>
          <p className="hero-description">You code. It grows.<br/>A small, living reminder of the things you make.</p>
          <Download/>
          <p className="works-with"><span className="works-label">Made for your coding companions</span><span className="separator" aria-hidden="true"/><span className="agent"><span className="agent-mark codex-mark" aria-hidden="true">✳</span> Codex</span><span className="separator" aria-hidden="true"/><span className="agent"><span className="agent-mark claude-mark" aria-hidden="true">✴</span> Claude Code</span></p>
        </div>
        <div className="hero-garden" aria-label="Illustration of the two plant families">
          <div className="garden-disc"/>
          <span className="garden-doodle doodle-a" aria-hidden="true">✦</span><span className="garden-doodle doodle-b" aria-hidden="true">✧</span>
          <Plant className="hero-codex" eager label="Codex illustration: a sage planter with rounded green leaves and small white, pink and yellow flowers"/>
          <Plant provider="claude" variant="blossom" className="hero-claude" eager label="Claude Code illustration: a terracotta pot with long leaves, orange daisies and lilac stars"/>
          <span className="handwritten hero-note">a little company,<br/>while you make things.</span>
          <span className="art-note hero-art-note">Plant family illustrations</span>
        </div>
      </section>
      <div className="quiet-strip"><span>Grows with your rhythm</span><span aria-hidden="true">✳</span><span>Lives on your Mac</span><span aria-hidden="true">✳</span><span>Nothing to keep up with</span></div>

      <section className="desktop-section section wrap" aria-labelledby="desktop-title">
        <div className="section-heading"><span className="eyebrow">A small presence. A lovely difference.</span><h2 id="desktop-title">Make a little room<br/>for something <em>growing.</em></h2><p>On your desktop, while you work, or tucked into the menu bar.<br/>Always nearby. Never asking for your attention.</p></div>
        <div className="desktop-preview">
          <div className="desktop-menu"><span className="desktop-apple" aria-hidden="true">●</span><b>Finder</b><span>File</span><span>Edit</span><span>View</span><SproutIcon/><span>Wed 9:41 AM</span></div>
          <div className="desktop-message"><span className="desktop-flower" aria-hidden="true">✳</span><p>Space to make<br/>good things.</p></div>
          <div className="editor-preview" aria-hidden="true"><div className="editor-bar"><i/><i/><i/><span>a fresh start</span></div><div className="editor-lines"><span/><span/><span/><span/><span/><span/></div></div>
          <div className="floating-example"><Plant/><span className="hover-close" aria-hidden="true">×</span></div>
          <span className="preview-label">Illustrated desktop preview · hover over the plant</span>
        </div>
        <div className="display-options"><div><b>Menu bar only</b><p>A tiny garden, a click away.</p></div><div><b>While I work</b><p>Comes out when your agent gets busy.</p></div><div><b>Always with me</b><p>Your favorite corner, a little greener.</p></div></div>
      </section>

      <section className="how section wrap" id="how-it-works" aria-labelledby="how-title"><div className="section-heading"><span className="eyebrow">From your first seed</span><h2 id="how-title">You do your thing.<br/>Pot does its thing.</h2></div>
        <div className="steps"><article><div className="step-icon"><SproutIcon/></div><h3>Plant your first seed.</h3><p>Pot finds compatible local logs from Codex and Claude Code. Confirm your sources. No extra login.</p></article><article><div className="step-icon code-icon" aria-hidden="true">&lt; / &gt;</div><h3>Make something.</h3><p>Work as you normally do. Your real token activity becomes a little energy for your plant.</p></article><article><div className="step-icon bloom-icon" aria-hidden="true">✿</div><h3>See what grows.</h3><p>A new leaf. A tiny bud. A flower you weren’t expecting. Steady days make it grow; days away show.</p></article></div>
      </section>

      <section className="growth-section section" id="your-garden" aria-label="Procedural plant growth"><div className="wrap"><Growth/></div></section>

      <section className="stats-section section wrap" aria-labelledby="stats-title"><div className="stats-copy"><span className="eyebrow">A little perspective</span><h2 id="stats-title">See what your<br/>tokens are <em>worth.</em></h2><p>Your little companion comes with a clearer picture of your coding activity. Today’s tokens, a week at a glance, and their estimated value at public API prices.</p><p className="fine-print">Estimated API value is a reference, not a bill. Missing prices stay missing. Your plant never grows faster because you use a more expensive model.</p></div><div className="stats-illustration"><div className="stats-paper"><span className="stats-provider">Codex</span><span className="stats-alias">Your local garden</span><Plant className="stats-plant" stage={3}/><span className="example-label">Statistics layout preview</span><div className="stats-values"><div><strong>Tokens today</strong><span>Your real activity</span></div><div><strong>Estimated API value</strong><span>When a verified rate is available</span></div></div><div className="empty-chart" aria-label="Illustrated seven-day chart layout, without sample usage values">{['M','T','W','T','F','S','S'].map((day,i)=><div key={i}><span/><small>{day}</small></div>)}</div><p className="chart-note">A week of your rhythm, without a target.</p></div></div></section>

      <section className="families section wrap" aria-labelledby="families-title"><div className="section-heading"><span className="eyebrow">Two companions. Their own nature.</span><h2 id="families-title">Same garden.<br/>Different personalities.</h2></div><div className="family-grid"><article className="family codex-family"><Plant/><div><h3>Codex</h3><p>Cool ceramic. Rounded leaves.<br/>A fresh, quietly curious nature.</p></div></article><article className="family claude-family"><Plant provider="claude"/><div><h3>Claude Code</h3><p>Warm terracotta. Expressive branches.<br/>A little wild, in the best way.</p></div></article></div><p className="section-footnote">Every plant grows from its own seed. What yours becomes is a little surprise.</p></section>

      <section className="privacy section wrap" id="privacy" aria-labelledby="privacy-title"><div className="privacy-symbol" aria-hidden="true"><SproutIcon/><span>⌂</span></div><span className="eyebrow">A garden, not a data farm</span><h2 id="privacy-title">Your garden<br/>stays <em>yours.</em></h2><p>On your Mac. In your own space.<br/>Pot keeps the garden and your usage statistics local.</p><div className="privacy-facts"><span>No Pot account</span><span>No app telemetry</span><span>Works offline</span></div><p className="privacy-detail">Pot reads compatible local logs to extract usage metrics. Conversations and code are discarded during parsing, never saved by Pot or sent to a server. You can delete Pot’s local garden whenever you choose.</p></section>

      <section className="download-section section" id="download" aria-labelledby="download-title"><div className="wrap download-inner"><div><span className="eyebrow">Something good is taking root</span><h2 id="download-title">Plant your<br/>first <em>seed.</em></h2><p>A little company for your next great idea.</p><Download/><p className="release-status">Free for macOS 14 or later.<br/>The download appears here as soon as the first release is published.<br/><a href="https://github.com/ClementeBobillier07/pot/releases">See releases on GitHub</a></p></div><Plant className="download-plant" stage={0}/></div></section>

      <section className="faq section wrap" aria-labelledby="faq-title"><div><span className="eyebrow">A few small questions</span><h2 id="faq-title">Good to know.</h2></div><div className="faq-items">{faqs.map(([q,a])=><details key={q}><summary>{q}<span aria-hidden="true">+</span></summary><p>{a}</p></details>)}</div></section>
    </main>
    <footer className="site-footer wrap"><a className="wordmark" href="#" aria-label="Pot home"><SproutIcon/>pot<span className="brand-period">.</span></a><p>A little plant on your Mac.</p><div><a href="https://github.com/ClementeBobillier07/pot">GitHub</a><a href="#privacy">Privacy</a><a href="https://github.com/ClementeBobillier07/pot/releases">Releases</a></div><span>Made to keep you company.</span></footer>
  </>;
}

function SproutIcon() { return <svg aria-hidden="true" viewBox="0 0 32 32" fill="none"><path d="M16 28V12" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round"/><path d="M16 20C4 22 3 7 16 15M17 13C17 2 31 4 17 16" fill="currentColor"/></svg>; }
