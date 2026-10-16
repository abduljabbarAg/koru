import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../local/write_intent.dart';
import '../models.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';

/// Changes an entry that already exists.
///
/// Every field is filled in with what is already stored, so opening and
/// cancelling cannot half-erase a meeting. The repeat rule is a dropdown rather
/// than a free field because "every week" and "weekly" have to mean one thing
/// between the parser and the form, and a typo in a recurring rule is a meeting
/// that quietly stops repeating.
///
/// The date and the time are text rather than pickers on purpose: the parser
/// accepts any reasonable string for both, and a picker would quietly reformat
/// what is stored. Both carry the stored format as their label so there is
/// nothing to guess.
class EventSheet extends ConsumerStatefulWidget {
  const EventSheet({super.key, required this.event});

  final CalendarEvent event;

  @override
  ConsumerState<EventSheet> createState() => _EventSheetState();
}

class _EventSheetState extends ConsumerState<EventSheet> {
  late final TextEditingController _title;
  late final TextEditingController _location;
  late final TextEditingController _date;
  late final TextEditingController _time;
  late final TextEditingController _duration;
  EventRecurrence? _recurrence;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.event;
    _title = TextEditingController(text: e.title);
    _location = TextEditingController(text: e.location ?? '');
    _date = TextEditingController(text: e.date);
    _time = TextEditingController(text: e.time ?? '');
    _duration = TextEditingController(
      text: e.durationMin == null ? '' : '${e.durationMin}',
    );
    _recurrence = e.recurrence;
  }

  @override
  void dispose() {
    _title.dispose();
    _location.dispose();
    _date.dispose();
    _time.dispose();
    _duration.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return KoruSheetBody(
      title: 'Change entry',
      subtitle: 'Everything is stored on this phone.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          KoruFieldStack(
            children: [
              TextField(
                controller: _title,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Title'),
              ),
              KoruFieldRow(
                children: [
                  TextField(
                    controller: _date,
                    decoration: const InputDecoration(labelText: 'Date (YYYY-MM-DD)'),
                  ),
                  TextField(
                    controller: _time,
                    decoration: const InputDecoration(labelText: 'Time (HH:mm)'),
                  ),
                ],
              ),
              TextField(
                controller: _location,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Where'),
              ),
              TextField(
                controller: _duration,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Length in minutes',
                  hintText: 'leave empty for the default',
                ),
              ),
              DropdownButtonFormField<EventRecurrence?>(
                value: _recurrence,
                decoration: const InputDecoration(labelText: 'Repeats'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Once')),
                  for (final r in EventRecurrence.values)
                    DropdownMenuItem(value: r, child: Text(_titleCase(r.phrase))),
                ],
                onChanged: (v) => setState(() => _recurrence = v),
              ),
            ],
          ),
          const SizedBox(height: KoruSpace.xl),
          Row(
            children: [
              TextButton(
                onPressed: _saving ? null : () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              const Spacer(),
              FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, KoruSize.buttonInCard),
                ),
                onPressed: _saving ? null : _save,
                child: const Text('Save'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _titleCase(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  Future<void> _save() async {
    setState(() => _saving = true);
    final store = await ref.read(storeProvider.future);
    final e = widget.event;
    final mins = int.tryParse(_duration.text.trim());

    await store.updateEvent(CalendarEvent(
      id: e.id,
      title: _title.text.trim().isEmpty ? e.title : _title.text.trim(),
      date: _date.text.trim(),
      time: _time.text.trim().isEmpty ? null : _time.text.trim(),
      location: _location.text.trim().isEmpty ? null : _location.text.trim(),
      durationMin: mins,
      recurrence: _recurrence,
      note: e.note,
      clientId: e.clientId,
      // A changed date or time means the phone's copy is out of date. Left
      // set, the entry would never sync again and the two calendars would
      // quietly disagree.
      synced: (_date.text.trim() == e.date &&
              (_time.text.trim().isEmpty ? null : _time.text.trim()) == e.time)
          ? e.synced
          : false,
      created: e.created,
    ));
    if (mounted) Navigator.pop(context, true);
  }
}