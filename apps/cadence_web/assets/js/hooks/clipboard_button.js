const ClipboardButton = {
  mounted() {
    this.onClick = () => this.copy()
    this.el.addEventListener("click", this.onClick)
  },

  destroyed() {
    this.el.removeEventListener("click", this.onClick)
  },

  async copy() {
    const text = this.absoluteText()

    try {
      await navigator.clipboard.writeText(text)
      this.markCopied()
    } catch (_error) {
      this.copyWithFallback(text)
      this.markCopied()
    }
  },

  absoluteText() {
    const value = this.el.dataset.clipboardText || window.location.pathname + window.location.search
    return new URL(value, window.location.origin).toString()
  },

  copyWithFallback(text) {
    const textarea = document.createElement("textarea")
    textarea.value = text
    textarea.setAttribute("readonly", "readonly")
    textarea.style.position = "fixed"
    textarea.style.opacity = "0"
    document.body.appendChild(textarea)
    textarea.select()
    document.execCommand("copy")
    textarea.remove()
  },

  markCopied() {
    this.el.dataset.clipboardCopied = "true"
    clearTimeout(this.clearCopiedTimer)
    this.clearCopiedTimer = setTimeout(() => {
      delete this.el.dataset.clipboardCopied
    }, 1500)
  }
}

export default ClipboardButton
