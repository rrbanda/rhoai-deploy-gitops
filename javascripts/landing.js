/**
 * Landing page dot navigation — tracks active section via Intersection Observer
 * and highlights the corresponding dot in the fixed left-side nav.
 * Only runs on pages that contain the .dot-nav element.
 */
(function () {
  "use strict";

  function init() {
    var dots = document.querySelectorAll(".dot-nav__dot");
    if (!dots.length) return;

    var sections = [];
    dots.forEach(function (dot) {
      var id = dot.getAttribute("href");
      if (!id || id.charAt(0) !== "#") return;
      var el = document.getElementById(id.slice(1));
      if (el) sections.push({ dot: dot, el: el });
    });

    if (!sections.length) return;

    var observer = new IntersectionObserver(
      function (entries) {
        entries.forEach(function (entry) {
          if (!entry.isIntersecting) return;
          dots.forEach(function (d) {
            d.classList.remove("dot-nav__dot--active");
          });
          for (var i = 0; i < sections.length; i++) {
            if (sections[i].el === entry.target) {
              sections[i].dot.classList.add("dot-nav__dot--active");
              break;
            }
          }
        });
      },
      { rootMargin: "-35% 0px -35% 0px", threshold: 0 }
    );

    sections.forEach(function (s) {
      observer.observe(s.el);
    });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }

  /* MkDocs Material instant-loading re-initializes pages without full reload */
  document.addEventListener("DOMContentSwitch", init);
})();
