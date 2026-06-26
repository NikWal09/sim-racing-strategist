/// Zakladka "Inzynier" — odpowiednik zakladki Inzynier z desktopu.
///
/// Start/Stop (PS5 albo tryb demo), status polaczenia i log zdarzen.
library;

import 'package:flutter/material.dart';

import '../app_settings.dart';
import '../app_state.dart';
import 'theme.dart';

class EngineerTab extends StatelessWidget {
  const EngineerTab({super.key, required this.controller});

  final TelemetryController controller;

  @override
  Widget build(BuildContext context) {
    final cc = context.appColors;
    String t(String k) => AppSettings.instance.t(k);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final running = controller.isRunning;
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    onPressed: running ? null : () => controller.connectPs5(),
                    icon: const Icon(Icons.wifi),
                    label: Text(t('engineer.startPs5')),
                  ),
                  OutlinedButton.icon(
                    onPressed: running ? null : () => controller.startDemo(),
                    icon: const Icon(Icons.play_circle_outline),
                    label: Text(t('engineer.demo')),
                  ),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: cc.danger),
                    onPressed: running ? () => controller.stop() : null,
                    icon: const Icon(Icons.stop),
                    label: Text(t('engineer.stop')),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.record_voice_over, size: 18, color: cc.muted),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(t('engineer.voice'),
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: cc.text)),
                  ),
                  const SizedBox(width: 8),
                  Switch(
                    value: controller.voiceEnabled,
                    onChanged: controller.setVoiceEnabled,
                  ),
                ],
              ),
              Text(controller.status, style: TextStyle(color: cc.muted2)),
              const SizedBox(height: 12),
              Text(t('engineer.eventLog'), style: TextStyle(color: cc.muted)),
              const SizedBox(height: 6),
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: cc.tileBottom,
                    border: Border.all(color: cc.stroke),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: ListView(
                    reverse: true,
                    children: [
                      for (final line in controller.log.reversed)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(line,
                              style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                  color: cc.text)),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
