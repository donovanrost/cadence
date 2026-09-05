<script lang="ts">
import { defineComponent, h, type PropType } from "vue";
import type { FieldPresentation } from "./widget_form_field";

const WidgetFormField = defineComponent({
  name: "WidgetFormField",
  props: {
    field: {
      type: Object as PropType<FieldPresentation>,
      required: true,
    },
  },
  setup(componentProps) {
    return () => {
      const field = componentProps.field;

      if (field.type === "checkbox") {
        return h("div", { class: field.wrapper_class }, [
          h("label", { class: "flex cursor-pointer items-start gap-3" }, [
            h("input", field.hidden_control?.attrs ?? {}),
            h("input", { ...field.control.attrs, class: field.control.class }),
            h("span", null, [
              field.label === null
                ? null
                : h("span", { class: field.label.class }, field.label.text),
              field.description === null
                ? null
                : h("span", { class: field.description.class }, field.description.text),
            ]),
          ]),
        ]);
      }

      const control =
        field.type === "select"
          ? h(
              "select",
              { ...field.control.attrs, class: field.control.class },
              field.control.options.map((option) =>
                h("option", { ...option.attrs, key: option.key }, option.text),
              ),
            )
          : h("input", { ...field.control.attrs, class: field.control.class });

      return h("div", { class: field.wrapper_class }, [
        h("label", null, [
          field.label === null ? null : h("span", { class: field.label.class }, field.label.text),
          control,
        ]),
        ...field.errors.map((error, index) =>
          h("p", { class: error.class, key: `${field.key}-error-${index}` }, error.text),
        ),
      ]);
    };
  },
});

export default WidgetFormField;
</script>
