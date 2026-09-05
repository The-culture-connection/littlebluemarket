import 'package:flutter/material.dart';

import '../app_assets.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'product_art.dart';

// ---------------------------------------------------------------- surfaces

/// A floating card. Cards sit on the blue with gaps between them rather than
/// hairline dividers, which is most of why the app reads as soft.
class LbmCard extends StatelessWidget {
  const LbmCard({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.margin = EdgeInsets.zero,
    this.onTap,
    this.color,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: margin,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color ?? c.surface,
          borderRadius: LbmRadius.cardR,
          boxShadow: c.shadowSoft,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            borderRadius: LbmRadius.cardR,
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}

/// The italic Fraunces label that introduces a group of cards.
class SectionHead extends StatelessWidget {
  const SectionHead(this.label, {super.key, this.trailing});

  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      label,
      style: LbmText.sectionLabel.copyWith(color: context.c.ink2),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 9),
      child: trailing == null
          ? text
          : Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [Expanded(child: text), trailing!],
            ),
    );
  }
}

/// A tappable row inside a card. Rows after the first carry a hairline of
/// `skyWash` rather than a divider colour.
class ListRow extends StatelessWidget {
  const ListRow({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.divided = false,
    this.crossAxisAlignment = CrossAxisAlignment.center,
    this.titleStyle,
    this.background,
    this.borderRadius,
  });

  final Widget? leading;
  final Widget title;
  final Widget? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool divided;
  final CrossAxisAlignment crossAxisAlignment;
  final TextStyle? titleStyle;
  final Color? background;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        crossAxisAlignment: crossAxisAlignment,
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 12)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                DefaultTextStyle.merge(
                  style:
                      titleStyle ??
                      TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                        color: c.ink,
                      ),
                  child: title,
                ),
                if (subtitle != null)
                  DefaultTextStyle.merge(
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.4,
                      color: c.ink3,
                    ),
                    child: subtitle!,
                  ),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 10), trailing!],
        ],
      ),
    );

    final content = DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: borderRadius,
        border: divided
            ? Border(top: BorderSide(color: c.skyWash))
            : null,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: borderRadius,
          child: row,
        ),
      ),
    );
    return content;
  }
}

/// Stacks [children] as rows inside a card, hairlining every row after the
/// first the way `.listrow + .listrow` does.
class RowStack extends StatelessWidget {
  const RowStack({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < children.length; i++)
          DecoratedBox(
            decoration: BoxDecoration(
              border: i == 0 ? null : Border(top: BorderSide(color: c.skyWash)),
            ),
            child: children[i],
          ),
      ],
    );
  }
}

// ----------------------------------------------------------------- buttons

/// Which fill a [PillButton] wears.
enum PillStyle {
  /// The solid accent fill. Uses `accentDeep` under `accentInk`, which is the
  /// whole point of the accent split — the pure accent is not readable under
  /// white in light mode.
  solid,

  /// Surface with a `skyMist` ring.
  ghost,

  /// A quiet `skyMist` fill carrying ink.
  quiet,
}

/// The pill button. Buttons are fully rounded everywhere in this design.
class PillButton extends StatelessWidget {
  const PillButton(
    this.label, {
    super.key,
    this.onPressed,
    this.style = PillStyle.solid,
    this.small = false,
    this.icon,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final PillStyle style;

  /// `.btn.sm` — tighter padding, smaller type, and sized to its content.
  final bool small;
  final IconData? icon;

  /// Whether the button fills its parent's width.
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final (Color bg, Color fg, Border? ring) = switch (style) {
      PillStyle.solid => (c.accentDeep, c.accentInk, null),
      PillStyle.ghost => (
        c.surface,
        c.ink,
        Border.all(color: c.skyMist, width: 1.5),
      ),
      PillStyle.quiet => (c.skyMist, c.ink, null),
    };

    final child = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon, size: small ? 17 : 19, color: fg),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: kBodyFont,
              fontSize: small ? 13.5 : 15,
              fontWeight: FontWeight.w800,
              height: 1.2,
              color: fg,
            ),
          ),
        ),
      ],
    );

    final button = DecoratedBox(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: LbmRadius.pillR,
        border: ring,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onPressed,
          borderRadius: LbmRadius.pillR,
          child: Padding(
            padding: small
                ? const EdgeInsets.symmetric(horizontal: 16, vertical: 9)
                : const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: child,
          ),
        ),
      ),
    );

    if (!expand) return button;
    return SizedBox(width: double.infinity, child: button);
  }
}

/// The 38pt circular icon button used in app bars and post actions.
class CircleIconButton extends StatelessWidget {
  const CircleIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.bare = false,
    this.color,
    this.background,
    this.size = 38,
    this.iconSize = 20,
    this.badge = false,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;

  /// `.iconbtn.bare` — no fill, no shadow.
  final bool bare;
  final Color? color;
  final Color? background;
  final double size;
  final double iconSize;

  /// The small accent dot used for unread state.
  final bool badge;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    Widget button = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bare ? null : (background ?? c.surface),
        shape: BoxShape.circle,
        boxShadow: bare ? null : c.shadowSoft,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          child: Icon(icon, size: iconSize, color: color ?? c.ink),
        ),
      ),
    );

    if (badge) {
      button = Stack(
        clipBehavior: Clip.none,
        children: [
          button,
          Positioned(
            top: 4,
            right: 4,
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: c.accentDeep,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      );
    }

    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}

// ------------------------------------------------------------------- chips

enum ChipStyle {
  /// `skyMist` on ink — the default.
  plain,

  /// An initiative hashtag: `accentMist` on `accentText`.
  initiative,

  /// The selected chip in a scope row: a solid `accentDeep` fill.
  on,

  /// The quietest fill, `skyWash` on secondary ink.
  quiet,
}

class LbmChip extends StatelessWidget {
  const LbmChip(
    this.label, {
    super.key,
    this.style = ChipStyle.plain,
    this.onTap,
    this.fontSize = 12,
    this.trailingIcon,
  });

  final String label;
  final ChipStyle style;
  final VoidCallback? onTap;
  final double fontSize;
  final IconData? trailingIcon;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final (Color bg, Color fg) = switch (style) {
      ChipStyle.plain => (c.skyMist, c.ink),
      ChipStyle.initiative => (c.accentMist, c.accentText),
      ChipStyle.on => (c.accentDeep, c.accentInk),
      ChipStyle.quiet => (c.skyWash, c.ink2),
    };

    return DecoratedBox(
      decoration: BoxDecoration(color: bg, borderRadius: LbmRadius.pillR),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: LbmRadius.pillR,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: fontSize,
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                      color: fg,
                    ),
                  ),
                ),
                if (trailingIcon != null) ...[
                  const SizedBox(width: 4),
                  Icon(trailingIcon, size: fontSize + 2, color: fg),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A wrapped run of hashtag chips. Tapping one searches for it.
class TagChips extends StatelessWidget {
  const TagChips(
    this.tags, {
    super.key,
    this.onTap,
    this.style = ChipStyle.initiative,
    this.trailing = const [],
  });

  final List<String> tags;
  final ValueChanged<String>? onTap;
  final ChipStyle style;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    if (tags.isEmpty && trailing.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 7,
      runSpacing: 7,
      children: [
        for (final tag in tags)
          LbmChip(
            tag,
            style: style,
            onTap: onTap == null ? null : () => onTap!(tag),
          ),
        ...trailing,
      ],
    );
  }
}

// ----------------------------------------------------------------- avatars

enum AvatarSize {
  xs(25, 10),
  sm(31, 12),
  md(38, 14),
  lg(78, 27);

  const AvatarSize(this.diameter, this.fontSize);
  final double diameter;
  final double fontSize;
}

/// A person's avatar: their initials on their own tint.
class Avatar extends StatelessWidget {
  const Avatar(
    this.person, {
    super.key,
    this.size = AvatarSize.md,
    this.onTap,
  });

  final Person person;
  final AvatarSize size;

  /// Every avatar in the app taps through to that person's feed.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final initials = Container(
      width: size.diameter,
      height: size.diameter,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Color(person.tint),
        shape: BoxShape.circle,
      ),
      child: Text(
        person.initials,
        style: TextStyle(
          fontFamily: kDisplayFont,
          fontWeight: FontWeight.w700,
          fontSize: size.fontSize,
          height: 1,
          color: Colors.white,
        ),
      ),
    );

    // A real photograph when there is one; the tinted initials are the fallback
    // and also what shows while the photo loads or if it fails.
    final photo = person.avatarUrl;
    final circle = photo == null
        ? initials
        : ClipOval(
            child: SizedBox(
              width: size.diameter,
              height: size.diameter,
              child: ProductPhoto(url: photo, fallback: initials),
            ),
          );
    if (onTap == null) return circle;
    return Semantics(
      button: true,
      label: '${person.name}, open their feed',
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: circle,
      ),
    );
  }
}

// ------------------------------------------------------------------- stars

/// A five-star rating. Drawn with icons rather than `★` so it renders the same
/// on every device regardless of font coverage.
class Stars extends StatelessWidget {
  const Stars(this.rating, {super.key, this.size = 13});

  final double rating;
  final double size;

  @override
  Widget build(BuildContext context) {
    final filled = rating.round().clamp(0, 5);
    return Semantics(
      label: '${rating.toStringAsFixed(1)} out of 5',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 5; i++)
            Padding(
              padding: const EdgeInsets.only(right: 0.6),
              child: Icon(
                i < filled ? Icons.star_rounded : Icons.star_outline_rounded,
                size: size + 2,
                color: context.c.accent,
              ),
            ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ fields

/// A read-only display field. The prototype's inputs are all `readonly`; these
/// carry real controllers so the screens work as forms once wired up.
class LbmField extends StatelessWidget {
  const LbmField({
    super.key,
    this.label,
    this.controller,
    this.initialValue,
    this.hintText,
    this.maxLines = 1,
    this.pill = false,
    this.onDark = false,
    this.keyboardType,
    this.readOnly = false,
    this.autofocus = false,
    this.textInputAction,
    this.onSubmitted,
    this.helper,
    this.obscureText = false,
    this.autofillHints,
  });

  final String? label;
  final TextEditingController? controller;
  final String? initialValue;
  final String? hintText;
  final int maxLines;

  /// Composers use a fully rounded field instead of the 16pt one.
  final bool pill;

  /// Fields on the onboarding blue invert to a translucent white.
  final bool onDark;
  final TextInputType? keyboardType;
  final bool readOnly;
  final bool autofocus;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final String? helper;

  /// A password field. Forces [maxLines] to 1 — Flutter asserts otherwise.
  final bool obscureText;

  /// Lets the platform password manager offer to fill and to save. Worth
  /// having: an app that cannot be autofilled trains people into worse
  /// passwords.
  final Iterable<String>? autofillHints;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final radius = pill ? LbmRadius.pillR : LbmRadius.fieldR;

    final fill = onDark
        ? Colors.white.withValues(alpha: 0.16)
        : c.surface;
    final border = onDark
        ? Colors.white.withValues(alpha: 0.34)
        : c.skyMist;
    final ink = onDark ? LbmConst.onWelcome : c.ink;
    final hintInk = onDark
        ? LbmConst.onWelcome.withValues(alpha: 0.66)
        : c.ink3;

    final field = TextField(
      controller: controller,
      readOnly: readOnly,
      autofocus: autofocus,
      obscureText: obscureText,
      autofillHints: autofillHints,
      maxLines: obscureText ? 1 : maxLines,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      onSubmitted: onSubmitted,
      cursorColor: onDark ? LbmConst.onWelcome : c.accent,
      style: TextStyle(
        fontFamily: kBodyFont,
        fontSize: 14.5,
        height: 1.45,
        color: ink,
      ),
      decoration: InputDecoration(
        isDense: true,
        hintText: hintText,
        hintStyle: TextStyle(
          fontFamily: kBodyFont,
          fontSize: 14.5,
          color: hintInk,
        ),
        filled: true,
        fillColor: fill,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 13,
        ),
        border: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: border, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: border, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(
            color: onDark ? LbmConst.onWelcome : c.accent,
            width: 1.8,
          ),
        ),
      ),
    );

    if (label == null && helper == null) return field;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null) ...[
          Text(
            label!,
            style: LbmText.fieldLabel.copyWith(
              color: onDark
                  ? LbmConst.onWelcome.withValues(alpha: 0.8)
                  : c.ink2,
            ),
          ),
          const SizedBox(height: 6),
        ],
        field,
        if (helper != null) ...[
          const SizedBox(height: 8),
          Text(
            helper!,
            style: LbmText.xtiny.copyWith(color: c.ink3, height: 1.55),
          ),
        ],
      ],
    );
  }
}

/// The rounded search pill used as a button on the feed and as a header
/// elsewhere.
class SearchPill extends StatelessWidget {
  const SearchPill({
    super.key,
    required this.label,
    this.onTap,
    this.strong = false,
  });

  final String label;
  final VoidCallback? onTap;

  /// A committed query renders in ink rather than placeholder grey.
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: LbmRadius.pillR,
        boxShadow: c.shadowSoft,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: LbmRadius.pillR,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(Icons.search_rounded, size: 18, color: c.ink3),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: strong ? FontWeight.w700 : FontWeight.w400,
                      color: strong ? c.ink : c.ink3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The "Near me" toggle beside the search pill.
class NearMeButton extends StatelessWidget {
  const NearMeButton({super.key, required this.active, this.onTap});

  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: active ? c.accentDeep : c.surface,
        borderRadius: LbmRadius.pillR,
        boxShadow: c.shadowSoft,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: LbmRadius.pillR,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.place_outlined,
                  size: 15,
                  color: active ? c.accentInk : c.ink2,
                ),
                const SizedBox(width: 6),
                Text(
                  'Near me',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: active ? c.accentInk : c.ink2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The two-up segmented control used on profiles and Shipping.
class SegmentedTabs extends StatelessWidget {
  const SegmentedTabs({
    super.key,
    required this.labels,
    required this.selected,
    required this.onChanged,
    this.padding = const EdgeInsets.fromLTRB(14, 14, 14, 10),
  });

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onChanged;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: padding,
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: i == selected ? c.accentDeep : c.skyWash,
                  borderRadius: LbmRadius.pillR,
                ),
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    onTap: () => onChanged(i),
                    borderRadius: LbmRadius.pillR,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 10,
                      ),
                      child: Text(
                        labels[i],
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: i == selected ? c.accentInk : c.ink2,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A run of text with `#hashtags` picked out in bold.
///
/// Hashtags are a controlled vocabulary, so highlighting them is meaningful
/// rather than decorative.
class HashtagText extends StatelessWidget {
  const HashtagText(
    this.text, {
    super.key,
    this.style,
    this.tagColor,
    this.onTagTap,
  });

  final String text;
  final TextStyle? style;
  final Color? tagColor;
  final ValueChanged<String>? onTagTap;

  static final _pattern = RegExp(r'#\w+');

  @override
  Widget build(BuildContext context) {
    final base = style ?? DefaultTextStyle.of(context).style;
    final spans = <InlineSpan>[];
    var index = 0;
    for (final match in _pattern.allMatches(text)) {
      if (match.start > index) {
        spans.add(TextSpan(text: text.substring(index, match.start)));
      }
      spans.add(
        TextSpan(
          text: match[0],
          style: TextStyle(fontWeight: FontWeight.w800, color: tagColor),
        ),
      );
      index = match.end;
    }
    if (index < text.length) spans.add(TextSpan(text: text.substring(index)));
    return Text.rich(TextSpan(style: base, children: spans));
  }
}

/// A "go further" link: a label followed by a drawn arrow.
///
/// The arrow is an icon rather than a `→` character because neither Nunito nor
/// Fraunces carries that glyph, and relying on the platform's font fallback
/// gets you a mismatched arrow at best and a tofu box at worst.
class InlineLink extends StatelessWidget {
  const InlineLink(
    this.label, {
    super.key,
    this.onTap,
    this.fontSize = 12,
    this.color,
  });

  final String label;
  final VoidCallback? onTap;
  final double fontSize;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final fg = color ?? context.c.skyDeep;
    return InkWell(
      onTap: onTap,
      borderRadius: LbmRadius.pillR,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.w800,
                color: fg,
              ),
            ),
          ),
          const SizedBox(width: 3),
          Icon(Icons.arrow_forward_rounded, size: fontSize + 2, color: fg),
        ],
      ),
    );
  }
}

/// The card that tells a guest what they are missing.
class GuestBanner extends StatelessWidget {
  const GuestBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 4, 14, 12),
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
      decoration: BoxDecoration(
        color: c.accentMist,
        borderRadius: const BorderRadius.all(Radius.circular(18)),
      ),
      child: Row(
        children: [
          Image.asset(LbmAssets.cartMark, width: 32),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              'Looking around as a guest — sign up to buy, post, or join the '
              'community.',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                height: 1.45,
                color: c.accentText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
