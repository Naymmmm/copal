export default {
  logo: <strong style={{ fontFamily: 'Space Grotesk, sans-serif', fontSize: '1.5rem', letterSpacing: '-0.02em' }}>Copal Docs</strong>,
  project: {
    link: 'https://github.com/Naymmmm/copal',
  },
  docsRepositoryBase: 'https://github.com/Naymmmm/copal/blob/main/docs',
  useNextSeoProps() {
    return {
      titleTemplate: '%s – Copal'
    }
  },
  navigation: {
    prev: true,
    next: true
  },
  footer: {
    text: (
      <span style={{ fontFamily: 'Space Grotesk, sans-serif' }}>
        Apache 2.0 {new Date().getFullYear()} © Naymmmm.
      </span>
    )
  },
  head: (
    <>
      <link rel="preconnect" href="https://fonts.googleapis.com" />
      <link rel="preconnect" href="https://fonts.gstatic.com" crossOrigin="anonymous" />
      <link href="https://fonts.googleapis.com/css2?family=Space+Grotesk:wght@300;400;500;600;700&family=JetBrains+Mono:wght@400;500;600&display=swap" rel="stylesheet" />
      <meta name="viewport" content="width=device-width, initial-scale=1.0" />
      <meta name="description" content="Copal is a powerful, modular AI Agent Swarm framework written in Luau." />
      <meta property="og:title" content="Copal — AI Agent Swarm Framework" />
      <meta property="og:description" content="Orchestrate hierarchies of AI models to solve complex tasks autonomously." />
    </>
  ),
  darkMode: false,
  nextThemes: {
    defaultTheme: 'light',
    forcedTheme: 'light'
  }
}