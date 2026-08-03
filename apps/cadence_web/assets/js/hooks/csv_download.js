// Client-side CSV download for the widget inspect panel. The server renders
// the CSV payload into data-csv; this hook turns it into a Blob download so
// no HTTP route (or extra auth surface) is needed.
export default {
  mounted() {
    this.onClick = () => {
      const blob = new Blob([this.el.dataset.csv || ""], {type: "text/csv;charset=utf-8"})
      const url = URL.createObjectURL(blob)
      const anchor = document.createElement("a")
      anchor.href = url
      anchor.download = this.el.dataset.filename || "widget-data.csv"
      anchor.click()
      URL.revokeObjectURL(url)
    }

    this.el.addEventListener("click", this.onClick)
  },

  destroyed() {
    this.el.removeEventListener("click", this.onClick)
  }
}
