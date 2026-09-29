/**
 * What a donation line looks like, going out and coming back.
 *
 * Its own module, and it imports nothing: `donations.ts` needs `toCents` from
 * `orders.ts`, and `orders.ts` needs to recognise a gift, so putting these
 * two functions in either of those files makes the pair of them circular.
 * They are pure, which is also the only way the money path can be tested
 * without a network.
 */

/**
 * The line attribute that says "this is a gift, not a sale".
 *
 * Stamped by the two places that make a donation line and read by the paid
 * webhook. One string in one file, because a typo in either half would
 * quietly credit a vendor for somebody's donation.
 */
export const DONATION_ATTRIBUTE = 'app_donation';

/** A cart line for a gift. No `app_seller_uid`: nobody is selling this. */
export interface DonationLine {
  merchandiseId: string;
  quantity: number;
  attributes: Array<{ key: string; value: string }>;
}

/**
 * The `funding/{yyyy-mm}` document a gift belongs to. Pure, and in UTC.
 *
 * `Funding.monthOf` in the app is the same format read off the phone's own
 * clock. They can disagree for a few hours on the first of the month, in
 * which case a phone reads a document that has not been written yet and the
 * page shows dashes, which is what it shows for a month with no data
 * anyway. The alternative is a server that guesses a timezone.
 */
export function fundingMonth(when: Date): string {
  const year = when.getUTCFullYear().toString().padStart(4, '0');
  const month = (when.getUTCMonth() + 1).toString().padStart(2, '0');
  return `${year}-${month}`;
}

/** How much of an order was a gift, in cents. Pure. */
export function donationCentsIn(
  lines: Array<{ unitPriceCents: number; quantity: number; donation?: boolean }>,
): number {
  return lines.reduce(
    (sum, line) =>
      line.donation ? sum + line.unitPriceCents * line.quantity : sum,
    0,
  );
}

/** The numeric tail of a `gid://shopify/Product/12345`. Pure. */
export function numericId(gid: string): string {
  return (gid.split('/').pop() ?? '').trim();
}

/**
 * Whether one order line is a gift rather than a sale. Pure.
 *
 * Two signals, because the two front doors are different. A line the app made
 * carries `app_donation`, which needs no lookup and cannot drift. A line
 * bought on the website carries nothing, so it is recognised by being a
 * configured donation product *and* needing no shipping: either test alone
 * would be wrong, since a digital product that is not a donation also needs
 * no shipping, and a donation product's id is only a gift when the line is
 * not a physical thing somebody is owed.
 */
export function isDonationItem(
  item: {
    requires_shipping?: unknown;
    product_id?: unknown;
    properties?: Array<{ name?: string; key?: string; value?: string }>;
  },
  donationProductIds: ReadonlySet<string> = new Set<string>(),
): boolean {
  for (const entry of item.properties ?? []) {
    if ((entry.name ?? entry.key) === DONATION_ATTRIBUTE) return true;
  }
  if (item.requires_shipping === false && item.product_id != null) {
    return donationProductIds.has(String(item.product_id));
  }
  return false;
}
