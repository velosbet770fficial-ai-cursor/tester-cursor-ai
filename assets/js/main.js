/* =============================================================
   CeritaRandom — interaksi halaman (vanilla JS, tanpa dependensi)
   ============================================================= */
(function () {
  'use strict';

  var $ = function (sel, root) { return (root || document).querySelector(sel); };
  var $$ = function (sel, root) { return Array.prototype.slice.call((root || document).querySelectorAll(sel)); };
  var reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  /* ---------- mode gelap / terang ---------- */
  var root = document.documentElement;
  var themeBtn = $('#themeToggle');
  var stored = null;

  try { stored = localStorage.getItem('cr-theme'); } catch (e) { /* penyimpanan diblokir */ }

  function applyTheme(theme) {
    root.setAttribute('data-theme', theme);
    if (themeBtn) themeBtn.setAttribute('aria-pressed', theme === 'dark' ? 'true' : 'false');
  }

  applyTheme(stored || (window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light'));

  if (themeBtn) {
    themeBtn.addEventListener('click', function () {
      var next = root.getAttribute('data-theme') === 'dark' ? 'light' : 'dark';
      applyTheme(next);
      try { localStorage.setItem('cr-theme', next); } catch (e) { /* abaikan */ }
    });
  }

  /* ---------- navigasi ---------- */
  var header = $('#header');
  var nav = $('#nav');
  var navToggle = $('#navToggle');

  function setNav(open) {
    if (!nav || !navToggle) return;
    nav.classList.toggle('is-open', open);
    document.body.classList.toggle('nav-open', open);
    navToggle.setAttribute('aria-expanded', open ? 'true' : 'false');
    navToggle.setAttribute('aria-label', open ? 'Tutup menu' : 'Buka menu');
    document.body.style.overflow = open ? 'hidden' : '';
  }

  if (navToggle) {
    navToggle.addEventListener('click', function () {
      setNav(!nav.classList.contains('is-open'));
    });
  }

  $$('.nav a').forEach(function (link) {
    link.addEventListener('click', function () { setNav(false); });
  });

  document.addEventListener('click', function (event) {
    if (!nav || !nav.classList.contains('is-open')) return;
    if (nav.contains(event.target) || (navToggle && navToggle.contains(event.target))) return;
    setNav(false);
  });

  var dropToggle = $('.nav__toggle');
  var dropdown = $('#menu-kategori');

  if (dropToggle && dropdown) {
    dropToggle.addEventListener('click', function () {
      var open = !dropdown.classList.contains('is-open');
      dropdown.classList.toggle('is-open', open);
      dropToggle.setAttribute('aria-expanded', open ? 'true' : 'false');
    });
  }

  /* ---------- header lekat + bar progres ---------- */
  var progressBar = $('#progress span');
  var toTop = $('#toTop');

  function onScroll() {
    var y = window.scrollY || window.pageYOffset;
    if (header) header.classList.toggle('is-stuck', y > 8);

    if (progressBar) {
      var max = document.documentElement.scrollHeight - window.innerHeight;
      progressBar.style.width = (max > 0 ? (y / max) * 100 : 0) + '%';
    }

    if (toTop) toTop.hidden = y < 700;
  }

  var scrollQueued = false;
  window.addEventListener('scroll', function () {
    if (scrollQueued) return;
    scrollQueued = true;
    window.requestAnimationFrame(function () { onScroll(); scrollQueued = false; });
  }, { passive: true });
  onScroll();

  if (toTop) {
    toTop.addEventListener('click', function () {
      window.scrollTo({ top: 0, behavior: reduceMotion ? 'auto' : 'smooth' });
    });
  }

  /* ---------- animasi masuk ---------- */
  var revealer = null;

  if ('IntersectionObserver' in window && !reduceMotion) {
    revealer = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (!entry.isIntersecting) return;
        entry.target.classList.add('is-in');
        revealer.unobserve(entry.target);
      });
    }, { rootMargin: '0px 0px -8% 0px', threshold: 0.06 });

    $$('.reveal').forEach(function (el) { revealer.observe(el); });
  } else {
    $$('.reveal').forEach(function (el) { el.classList.add('is-in'); });
  }

  function watch(el) {
    if (revealer && !el.classList.contains('is-in')) revealer.observe(el);
  }

  /* ---------- tautan navigasi aktif ---------- */
  var sections = ['beranda', 'kategori', 'terbaru', 'random', 'receh', 'tentang']
    .map(function (id) { return document.getElementById(id); })
    .filter(Boolean);

  if ('IntersectionObserver' in window && sections.length) {
    var navLinks = $$('.nav__list .nav__link[href^="#"]');
    var spy = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (!entry.isIntersecting) return;
        navLinks.forEach(function (link) {
          link.classList.toggle('is-active', link.getAttribute('href') === '#' + entry.target.id);
        });
      });
    }, { rootMargin: '-45% 0px -50% 0px' });

    sections.forEach(function (section) { spy.observe(section); });
  }

  /* ---------- data cerita dari DOM ---------- */
  var grid = $('#storyGrid');
  var cards = grid ? $$('.story', grid) : [];

  function readCard(card) {
    var img = $('img', card);
    var chip = $('.chip', card);
    return {
      el: card,
      title: (card.getAttribute('data-title') || $('.story__title', card).textContent).trim(),
      excerpt: ($('.story__excerpt', card) || { textContent: '' }).textContent.trim(),
      cat: card.getAttribute('data-cat') || '',
      label: chip ? chip.textContent.trim() : 'Cerita',
      chipClass: chip ? chip.className : 'chip',
      img: img ? img.getAttribute('src') : '',
      alt: img ? img.getAttribute('alt') : '',
      href: ($('a', card) || { getAttribute: function () { return 'index.html'; } }).getAttribute('href')
    };
  }

  var stories = cards.map(readCard);

  $$('.feature, .story--row').forEach(function (card) {
    var img = $('img', card);
    var chip = $('.chip', card);
    if (!img || !chip) return;
    stories.push({
      el: card,
      title: (card.getAttribute('data-title') || '').trim() || $('h3', card).textContent.trim(),
      excerpt: ($('.feature__excerpt', card) || $('.story__excerpt', card) || { textContent: '' }).textContent.trim(),
      cat: card.getAttribute('data-cat') || '',
      label: chip.textContent.trim(),
      chipClass: chip.className,
      img: img.getAttribute('src'),
      alt: img.getAttribute('alt'),
      href: ($('a', card) || { getAttribute: function () { return 'index.html'; } }).getAttribute('href')
    });
  });

  /* ---------- saringan kategori + muat lebih banyak ---------- */
  var STEP = 6;
  var state = { filter: 'all', limit: 9 };
  var loadMore = $('#loadMore');
  var shownCount = $('#shownCount');
  var gridCount = $('.grid__count');
  var gridEmpty = $('#gridEmpty');

  function render() {
    var matched = cards.filter(function (card) {
      return state.filter === 'all' || card.getAttribute('data-cat') === state.filter;
    });

    matched.forEach(function (card, i) {
      var show = i < state.limit;
      card.classList.toggle('is-hidden', !show);
      if (show) watch(card);
    });

    cards.forEach(function (card) {
      if (matched.indexOf(card) === -1) card.classList.add('is-hidden');
    });

    var shown = Math.min(state.limit, matched.length);
    if (shownCount) shownCount.textContent = String(shown);
    if (gridCount) {
      gridCount.innerHTML = '<strong id="shownCount">' + shown + '</strong> dari ' + matched.length + ' cerita ditampilkan';
      shownCount = $('#shownCount');
    }
    if (gridEmpty) gridEmpty.hidden = matched.length !== 0;
    if (loadMore) {
      loadMore.hidden = matched.length <= shown;
      loadMore.classList.toggle('is-done', matched.length <= shown);
    }
  }

  $$('.pill[data-filter]').forEach(function (pill) {
    pill.addEventListener('click', function () {
      $$('.pill[data-filter]').forEach(function (other) { other.classList.remove('is-active'); });
      pill.classList.add('is-active');
      state.filter = pill.getAttribute('data-filter');
      state.limit = 9;
      render();
    });
  });

  if (loadMore) {
    loadMore.addEventListener('click', function () {
      state.limit += STEP;
      render();
    });
  }

  render();

  /* kategori di bagian atas ikut menyaring grid */
  $$('.cat[data-jump]').forEach(function (tile) {
    tile.addEventListener('click', function () {
      var target = tile.getAttribute('data-jump');
      var pill = $('.pill[data-filter="' + target + '"]');
      if (pill) pill.click();
    });
  });

  /* ---------- mesin cerita random ---------- */
  var randomCard = $('#randomCard');
  var randomBtn = $('#randomBtn');
  var randomAgain = $('#randomAgain');
  var spinCount = $('#spinCount');
  var spins = 0;
  var terakhir = [];

  function spin() {
    if (!randomCard || !stories.length) return;

    // hindari mengulang beberapa cerita terakhir supaya undiannya terasa berganti
    var jeda = Math.min(3, stories.length - 1);
    var idx = Math.floor(Math.random() * stories.length);
    for (var coba = 0; coba < 20 && terakhir.indexOf(idx) !== -1; coba++) {
      idx = Math.floor(Math.random() * stories.length);
    }
    terakhir.push(idx);
    if (terakhir.length > jeda) terakhir.shift();

    var story = stories[idx];
    var img = $('#randomImg');
    var chip = $('#randomChip');

    randomCard.classList.remove('is-spinning');
    void randomCard.offsetWidth;
    randomCard.classList.add('is-spinning');

    window.setTimeout(function () {
      if (img) { img.src = story.img; img.alt = story.alt; }
      if (chip) { chip.className = story.chipClass.replace(/\s*is-\w+/g, ''); chip.textContent = story.label; }
      $('#randomTitle').textContent = story.title;
      $('#randomExcerpt').textContent = story.excerpt;
      var link = $('.random-card__foot .btn--primary');
      if (link) link.setAttribute('href', story.href || 'index.html');
    }, reduceMotion ? 0 : 160);

    spins += 1;
    if (spinCount) spinCount.textContent = String(spins);
  }

  if (randomBtn) randomBtn.addEventListener('click', spin);
  if (randomAgain) randomAgain.addEventListener('click', spin);

  /* ---------- pencarian ---------- */
  var search = $('#search');
  var searchInput = $('#searchInput');
  var searchResults = $('#searchResults');

  var searchOpener = null;

  function openSearch() {
    if (!search) return;
    searchOpener = document.activeElement;
    search.hidden = false;
    document.body.style.overflow = 'hidden';
    window.setTimeout(function () { if (searchInput) searchInput.focus(); }, 30);
  }

  function closeSearch() {
    if (!search || search.hidden) return;
    search.hidden = true;
    document.body.style.overflow = '';
    if (searchInput) searchInput.blur();
    if (searchOpener && typeof searchOpener.focus === 'function') searchOpener.focus();
    searchOpener = null;
  }

  function escapeHtml(text) {
    return text.replace(/[&<>"']/g, function (ch) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[ch];
    });
  }

  function runSearch(term) {
    if (!searchResults) return;
    var q = term.trim().toLowerCase();

    if (q.length < 2) {
      searchResults.innerHTML = '<p class="search__hint">Ketik minimal dua huruf. Coba <em>mancing</em>, <em>kereta</em>, atau <em>kucing</em>.</p>';
      return;
    }

    var hits = stories.filter(function (story) {
      return (story.title + ' ' + story.excerpt + ' ' + story.label).toLowerCase().indexOf(q) !== -1;
    }).slice(0, 8);

    if (!hits.length) {
      searchResults.innerHTML = '<p class="search__none">Tidak ada cerita yang cocok dengan &ldquo;' +
        escapeHtml(term) + '&rdquo;. Coba kata lain, atau putar mesin random.</p>';
      return;
    }

    searchResults.innerHTML = hits.map(function (story) {
      return '<a class="search__item" href="' + (story.href || 'index.html') + '">' +
        '<img src="' + story.img + '" alt="" loading="lazy">' +
        '<span><strong>' + escapeHtml(story.title) + '</strong>' +
        '<span class="' + story.chipClass + '">' + escapeHtml(story.label) + '</span></span></a>';
    }).join('');
  }

  var searchOpen = $('#searchOpen');
  if (searchOpen) searchOpen.addEventListener('click', openSearch);
  $$('[data-close-search]').forEach(function (el) { el.addEventListener('click', closeSearch); });
  if (searchInput) {
    searchInput.addEventListener('input', function () { runSearch(searchInput.value); });
  }

  /* ---------- papan tombol ---------- */
  document.addEventListener('keydown', function (event) {
    var typing = /^(INPUT|TEXTAREA|SELECT)$/.test(document.activeElement.tagName);

    if (event.key === 'Escape') {
      closeSearch();
      setNav(false);
      return;
    }

    if (typing) return;

    if (event.key === '/') {
      event.preventDefault();
      openSearch();
    } else if (event.key === 'r' || event.key === 'R') {
      var target = $('#random');
      if (target && !randomCard) return;
      spin();
    }
  });

  /* ---------- penghitung angka ---------- */
  function formatNumber(value, suffix) {
    return value.toLocaleString('id-ID') + (suffix || '');
  }

  if ('IntersectionObserver' in window && !reduceMotion) {
    var counter = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (!entry.isIntersecting) return;
        var el = entry.target;
        counter.unobserve(el);

        var target = parseInt(el.getAttribute('data-count'), 10);
        var suffix = el.getAttribute('data-suffix') || '';
        if (isNaN(target)) return;

        var start = performance.now();
        var span = 1400;

        function step(now) {
          var progress = Math.min((now - start) / span, 1);
          var eased = 1 - Math.pow(1 - progress, 3);
          el.textContent = formatNumber(Math.round(target * eased), suffix);
          if (progress < 1) window.requestAnimationFrame(step);
        }

        el.textContent = formatNumber(0, suffix);
        window.requestAnimationFrame(step);
      });
    }, { threshold: 0.4 });

    $$('[data-count]').forEach(function (el) { counter.observe(el); });
  }

  /* ---------- formulir langganan ---------- */
  var toast = $('#toast');
  var toastTimer = null;

  function showToast(message) {
    if (!toast) return;
    toast.hidden = false;
    toast.textContent = message;
    void toast.offsetWidth;
    toast.classList.add('is-visible');
    window.clearTimeout(toastTimer);
    toastTimer = window.setTimeout(function () {
      toast.classList.remove('is-visible');
      window.setTimeout(function () { toast.hidden = true; }, 400);
    }, 4200);
  }

  $$('form[data-newsletter]').forEach(function (form) {
    form.addEventListener('submit', function (event) {
      event.preventDefault();
      var input = $('input[type="email"]', form);
      var value = input ? input.value.trim() : '';

      if (!value || !/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(value)) {
        showToast('Emailnya kurang lengkap. Coba cek lagi ya.');
        if (input) input.focus();
        return;
      }

      form.reset();
      showToast('Sip! ' + value + ' sudah masuk daftar. Cek inbox Jumat pagi.');
    });
  });

  /* ---------- tahun berjalan di footer ---------- */
  var yearHolder = $('[data-year]');
  if (yearHolder) yearHolder.textContent = String(new Date().getFullYear());
})();
