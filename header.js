(function () {
  var path = window.location.pathname;
  var isHome      = path === '/' || path === '/index.html';
  var isBlogIndex = path === '/blog' || path === '/blog/' || path === '/blog/index.html';

  var linkDefs = [
    { href: '/',     text: 'home', skip: isHome },
    { href: '/blog', text: 'blog', skip: isBlogIndex },
    { href: 'https://www.linkedin.com/in/vaidehisj/',     text: 'linkedin', external: true },
    { href: 'https://github.com/vaidehijoshi',            text: 'github',   external: true },
    { href: 'https://medium.com/@vaidehijoshi',           text: 'medium',   external: true },
    { href: 'https://bsky.app/profile/vaidehi.com',       text: 'bluesky',  external: true },
    { href: 'https://www.twitter.com/vaidehijoshi',       text: 'twitter',  external: true },
  ];

  var navHtml = linkDefs
    .filter(function (l) { return !l.skip; })
    .map(function (l) {
      var attrs = 'href="' + l.href + '"';
      if (l.external) attrs += ' target="_blank" rel="noopener noreferrer"';
      return '<a ' + attrs + '>' + l.text + '</a>';
    })
    .join('<span class="nav-sep"> · </span>');

  var header = document.getElementById('site-header');
  if (!header) return;
  header.innerHTML =
    '<div id="heading-content">' +
      '<a href="/"><img src="/vaidehi-white.png" class="vaidehi-logo-image" alt="Vaidehi Joshi"/></a>' +
    '</div>' +
    '<nav id="site-nav">' + navHtml + '</nav>' +
    '<label class="theme-toggle" aria-label="Toggle light/dark mode">' +
      '<input type="checkbox" id="theme-checkbox"/>' +
      '<span class="toggle-track"><span class="toggle-thumb"></span></span>' +
    '</label>';

  var checkbox = document.getElementById('theme-checkbox');
  var dark = document.documentElement.getAttribute('data-theme') === 'dark';
  checkbox.checked = dark;

  checkbox.addEventListener('change', function () {
    dark = checkbox.checked;
    document.documentElement.setAttribute('data-theme', dark ? 'dark' : '');
    localStorage.setItem('theme', dark ? 'dark' : 'light');
    document.dispatchEvent(new CustomEvent('themechange', { detail: { dark: dark } }));
  });
}());
