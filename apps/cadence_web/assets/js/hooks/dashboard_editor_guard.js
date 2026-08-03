const DashboardEditorGuard = {
  mounted() {
    this.beforeUnload = (event) => {
      if (!this.dirty()) return

      event.preventDefault()
      event.returnValue = ""
    }

    this.documentClick = (event) => {
      if (!this.dirty()) return

      const anchor = event.target.closest?.("a[href]")
      if (!anchor || anchor.hasAttribute("data-editor-discard")) return
      if (anchor.target === "_blank" || anchor.hasAttribute("download")) return

      if (!window.confirm("Discard unsaved dashboard changes and leave the Editor?")) {
        event.preventDefault()
        event.stopImmediatePropagation()
      }
    }

    window.addEventListener("beforeunload", this.beforeUnload)
    document.addEventListener("click", this.documentClick, true)
  },

  destroyed() {
    window.removeEventListener("beforeunload", this.beforeUnload)
    document.removeEventListener("click", this.documentClick, true)
  },

  dirty() {
    return this.el.dataset.editorDirty === "true"
  },
}

export default DashboardEditorGuard
