(() => {
  const button = document.getElementById("download-button");
  if (!button) return;

  const updateDownloadPosition = () => {
    const shouldDock = window.scrollY > Math.max(220, window.innerHeight * 0.42);
    button.classList.toggle("is-docked", shouldDock);
  };

  let ticking = false;
  window.addEventListener("scroll", () => {
    if (!ticking) {
      window.requestAnimationFrame(() => {
        updateDownloadPosition();
        ticking = false;
      });
      ticking = true;
    }
  }, { passive: true });

  window.addEventListener("resize", updateDownloadPosition);
  updateDownloadPosition();
})();
