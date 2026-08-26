(function () {
  "use strict";

  const wheels = window.TREAD_WHEELS;
  const list = document.getElementById("wheel-list");
  const search = document.getElementById("wheel-search");
  const emptyState = document.getElementById("empty-state");
  const markers = new Map();
  let activeNumber = null;

  const map = L.map("map", {
    zoomControl: false,
    minZoom: 4,
    maxZoom: 19,
    zoomSnap: 0.5,
  });

  map.attributionControl.setPrefix(false);

  L.control.zoom({ position: "topright" }).addTo(map);
  L.tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png", {
    maxZoom: 19,
    attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> Contributors',
  }).addTo(map);

  function pinIcon(number, active) {
    return L.divIcon({
      className: "numbered-pin-shell",
      html: `<span class="numbered-pin${active ? " is-active" : ""}"><b>${number}</b></span>`,
      iconSize: [38, 46],
      iconAnchor: [19, 44],
      popupAnchor: [0, -43],
    });
  }

  function popupContent(wheel) {
    const card = document.createElement("article");
    card.className = "wheel-card";

    const image = document.createElement("img");
    image.src = wheel.image;
    image.alt = `車輪 No.${wheel.number}`;
    image.width = 533;
    image.height = 800;

    const label = document.createElement("p");
    label.textContent = `No.${wheel.number}`;

    card.append(image, label);
    return card;
  }

  function setActive(number) {
    if (activeNumber !== null && markers.has(activeNumber)) {
      markers.get(activeNumber).setIcon(pinIcon(activeNumber, false));
    }
    activeNumber = number;
    markers.get(number).setIcon(pinIcon(number, true));

    document.querySelectorAll(".wheel-button").forEach((button) => {
      const isActive = Number(button.dataset.number) === number;
      button.classList.toggle("is-active", isActive);
      button.setAttribute("aria-current", isActive ? "true" : "false");
    });
  }

  function focusWheel(number, fromList) {
    const wheel = wheels.find((item) => item.number === number);
    const marker = markers.get(number);
    if (!wheel || !marker) return;

    setActive(number);
    map.flyTo([wheel.lat, wheel.lng], 16, { duration: 0.85 });
    window.setTimeout(() => marker.openPopup(), 500);

    if (fromList && window.matchMedia("(max-width: 759px)").matches) {
      document.querySelector(".map-panel").scrollIntoView({ behavior: "smooth", block: "start" });
    }
  }

  wheels.forEach((wheel) => {
    const marker = L.marker([wheel.lat, wheel.lng], {
      icon: pinIcon(wheel.number, false),
      title: `No.${wheel.number}`,
      keyboard: true,
    })
      .bindPopup(() => popupContent(wheel), {
        className: "wheel-popup",
        closeButton: true,
        maxWidth: 250,
        minWidth: 190,
      })
      .on("click", () => setActive(wheel.number))
      .addTo(map);

    markers.set(wheel.number, marker);
  });

  const bounds = L.latLngBounds(wheels.map((wheel) => [wheel.lat, wheel.lng]));
  map.fitBounds(bounds.pad(0.12));

  function renderList(query) {
    const normalized = query.trim().replace(/^no\.?/i, "");
    const filtered = normalized
      ? wheels.filter((wheel) => String(wheel.number).includes(normalized))
      : wheels;

    list.replaceChildren();
    filtered.forEach((wheel) => {
      const button = document.createElement("button");
      button.type = "button";
      button.className = "wheel-button";
      button.dataset.number = String(wheel.number);
      button.setAttribute("aria-label", `車輪 No.${wheel.number} の位置を表示`);
      button.setAttribute("aria-current", wheel.number === activeNumber ? "true" : "false");
      button.innerHTML = `<span>No.</span><strong>${wheel.number}</strong><i aria-hidden="true">→</i>`;
      if (wheel.number === activeNumber) button.classList.add("is-active");
      button.addEventListener("click", () => focusWheel(wheel.number, true));
      list.append(button);
    });

    emptyState.hidden = filtered.length > 0;
  }

  search.addEventListener("input", (event) => renderList(event.target.value));
  renderList("");

  window.addEventListener("resize", () => map.invalidateSize());
  window.setTimeout(() => map.invalidateSize(), 120);
})();
