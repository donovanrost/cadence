import {
  decoders as d,
  oneItem,
  perItem,
  type PerItem,
  type PerItemOptions,
  type Unshown,
} from "@/api/index.ts";
import { attentionReader, type Attention } from "@/features/now/index.ts";

/**
 * U86 (lead): a pass's attention items, read one by one. An item this console can't read is left
 * out and described, so the pass, and every other pass in its list, still shows.
 */
const options: PerItemOptions<Attention> = {
  label: "A pass's attention items",
  kindOf: (raw) => [raw["source"]],
};
/** `attention`: the pass's top item (U31/U32), the queue's object. */
export const passAttention = oneItem(attentionReader, options);
/** `attentions`: every open item on the pass (U45). */
export const passAttentionList = perItem(attentionReader, 50, options);

type Read = Readonly<{
  attention: PerItem<Attention> | null | undefined;
  attentions: PerItem<Attention> | undefined;
}>;
export type WithAttentions<T extends Read> = Omit<T, keyof Read> &
  Readonly<{
    attention: Attention | null | undefined;
    attentions: readonly Attention[] | undefined;
    /** U86: `attention` was sent but couldn't be read (it reads null). */
    attention_unshown?: Unshown;
    /** U86: the items of `attentions` that couldn't be read. */
    attentions_unshown?: readonly Unshown[];
  }>;

/** The pass as screens use it: readable items in place, the unreadable ones beside them. */
export function withPassAttentions<T extends Read>(read: d.Reader<T>): d.Reader<WithAttentions<T>> {
  return (value, path = "") => {
    const { attention, attentions, ...rest } = read(value, path);
    const top = attention?.unshown[0];
    return {
      ...rest,
      attention: attention ? (attention.items[0] ?? null) : attention,
      attentions: attentions?.items,
      ...(top ? { attention_unshown: top } : {}),
      ...(attentions?.unshown.length ? { attentions_unshown: attentions.unshown } : {}),
    };
  };
}
