import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/async.dart';
import '../../widgets/primitives.dart';
import '../../widgets/screen.dart';

/// The hidden dev screen: who the phone thinks it is, and whether the
/// deployed backend can reach Shopify, the webhooks and Shipturtle.
///
/// Reached from the bottom of Edit Profile in debug builds. Everything on it
/// is copyable, because its whole purpose is to be pasted to Claude.
class DiagnosticsScreen extends ConsumerStatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  ConsumerState<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends ConsumerState<DiagnosticsScreen> {
  late Future<AuthFacts> _facts;
  Future<HealthReport>? _health;

  @override
  void initState() {
    super.initState();
    _facts = ref.read(diagnosticsRepositoryProvider).authFacts();
  }

  void _runHealth() {
    setState(() {
      _health = ref.read(diagnosticsRepositoryProvider).healthCheck();
    });
  }

  void _refreshFacts() {
    setState(() {
      _facts = ref.read(diagnosticsRepositoryProvider).authFacts();
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return LbmScreen(
      appBar: const LbmAppBar(title: 'Diagnostics (dev)'),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 26),
        children: [
          const SectionHead('This phone'),
          FutureBuilder<AuthFacts>(
            future: _facts,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return LbmErrorCard(
                  error: snapshot.error!,
                  onRetry: _refreshFacts,
                );
              }
              final facts = snapshot.data;
              if (facts == null) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                );
              }
              return _FactsCard(facts: facts, onRefresh: _refreshFacts);
            },
          ),
          const SizedBox(height: 18),
          const SectionHead('The backend'),
          LbmCard(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Asks the deployed functions whether they can reach the '
                  'store, the webhooks and Shipturtle. Takes a few seconds.',
                  style: LbmText.tiny.copyWith(color: c.ink2),
                ),
                const SizedBox(height: 12),
                PillButton(
                  _health == null ? 'Run backend health check' : 'Run again',
                  onPressed: _runHealth,
                ),
              ],
            ),
          ),
          if (_health != null) ...[
            const SizedBox(height: 10),
            FutureBuilder<HealthReport>(
              future: _health,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return LbmErrorCard(
                    error: snapshot.error!,
                    onRetry: _runHealth,
                  );
                }
                final report = snapshot.data;
                if (report == null) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  );
                }
                return _ReportCard(report: report);
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _FactsCard extends StatelessWidget {
  const _FactsCard({required this.facts, required this.onRefresh});

  final AuthFacts facts;
  final VoidCallback onRefresh;

  String get _text => [
    'backend:       ${facts.backend}',
    'uid:           ${facts.uid ?? '(signed out)'}',
    'email:         ${facts.email ?? '-'}',
    'anonymous:     ${facts.isAnonymous}',
    'emailVerified: ${facts.emailVerified}',
    'seller claim:  ${facts.isSeller}',
    'admin claim:   ${facts.isAdmin}',
    'isLinked:      ${facts.isLinked}',
  ].join('\n');

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return LbmCard(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Fact('Backend', facts.backend),
          _Fact('Account', facts.uid ?? 'signed out'),
          _Fact('Email', facts.email ?? '-'),
          _Fact('Guest', facts.isAnonymous ? 'yes' : 'no'),
          _Fact(
            'Email verified',
            facts.emailVerified ? 'yes' : 'no',
            good: facts.emailVerified,
          ),
          _Fact('Seller claim', facts.isSeller ? 'yes' : 'no'),
          _Fact('Admin claim', facts.isAdmin ? 'yes' : 'no'),
          _Fact('Linked to the store', facts.isLinked ? 'yes' : 'not yet'),
          const SizedBox(height: 10),
          Row(
            children: [
              PillButton(
                'Copy',
                small: true,
                expand: false,
                style: PillStyle.quiet,
                onPressed: () => Clipboard.setData(ClipboardData(text: _text)),
              ),
              const SizedBox(width: 6),
              PillButton(
                'Refresh',
                small: true,
                expand: false,
                style: PillStyle.ghost,
                onPressed: onRefresh,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Claims come from the token on this phone. If a grant happened '
            'and this still says no, the token has not refreshed.',
            style: LbmText.xtiny.copyWith(color: c.ink3),
          ),
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value, {this.good});

  final String label;
  final String value;
  final bool? good;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 128,
            child: Text(label, style: LbmText.tiny.copyWith(color: c.ink2)),
          ),
          Expanded(
            child: Text(
              value,
              style: LbmText.tiny.copyWith(
                fontWeight: FontWeight.w700,
                color: good == null ? c.ink : (good! ? c.sage : c.clay),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.report});

  final HealthReport report;

  String get _text {
    final buffer = StringBuffer()
      ..writeln('--- LBM backend health (paste to Claude) ---')
      ..writeln('project: ${report.project}')
      ..writeln('at:      ${report.at.toIso8601String()}');
    for (final check in report.checks) {
      buffer.writeln(
        '${check.ok ? 'PASS' : 'FAIL'}  ${check.name}: ${check.summary}',
      );
      if (!check.ok && check.fix != null) {
        buffer.writeln('      fix -> ${check.fix}');
      }
    }
    buffer.writeln('--------------------------------------------');
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return LbmCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RowStack(
            children: [
              for (final check in report.checks)
                ListRow(
                  leading: Icon(
                    check.ok ? Icons.check_circle_rounded : Icons.error_rounded,
                    size: 20,
                    color: check.ok ? c.sage : c.clay,
                  ),
                  title: Text(check.name),
                  subtitle: Text(
                    check.ok || check.fix == null
                        ? check.summary
                        : '${check.summary}\nfix: ${check.fix}',
                    maxLines: 6,
                    overflow: TextOverflow.ellipsis,
                  ),
                  crossAxisAlignment: CrossAxisAlignment.start,
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
            child: PillButton(
              'Copy report for Claude',
              small: true,
              expand: false,
              style: PillStyle.quiet,
              onPressed: () => Clipboard.setData(ClipboardData(text: _text)),
            ),
          ),
        ],
      ),
    );
  }
}
