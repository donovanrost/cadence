// Ops nav rail expand/collapse with localStorage persistence. The expanded
// state lives in a data attribute so Tailwind's data-[expanded] variants
// style both states; updated() re-applies it after LiveView patches.
const NavRail = {
  mounted() {
    this.storageKey = this.el.dataset.storageKey || "cadence-ops-rail"
    this.expanded = localStorage.getItem(this.storageKey) === "expanded"
    this.apply()

    this.el.addEventListener("click", (event) => {
      if (event.target.closest("[data-rail-toggle]")) {
        this.expanded = !this.expanded
        localStorage.setItem(this.storageKey, this.expanded ? "expanded" : "collapsed")
        this.apply()
      }
    })
  },

  updated() {
    this.apply()
  },

  apply() {
    if (this.expanded) {
      this.el.setAttribute("data-expanded", "")
    } else {
      this.el.removeAttribute("data-expanded")
    }
  },
}

export default NavRail
