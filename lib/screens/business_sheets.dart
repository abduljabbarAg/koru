import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../currency.dart';
import '../models.dart';
import '../state.dart';
import '../theme.dart';
import '../ui/celebration.dart';
import '../widgets.dart';

/// The three sheets the Clients and Revenue tabs open, and the writes behind
/// them.
///
/// They live here rather than inside the screen because the screen itself was
/// thirteen hundred lines and two thirds of that was form layout. Splitting them
/// out means a screen that draws things and a file that fills in forms can be
/// read apart, and the shared parts below — the field rhythm, the date button,
/// the invalidation list — are stated once instead of five times.
///
/// Nothing about what these write has changed. The amount is still required, the
/// deposit still goes into the ledger rather than being subtracted from the
/// invoice, and the due date is still worked out from the terms unless the
/// reader overrides it.

/// Create or edit a client.
Future<void> editClientSheet(
  BuildContext context,
  WidgetRef ref, {
  Client? existing,
}) async {
  // Read before the sheet opens, because the sheet is shown with this context
  // and using it after an await is exactly what the linter warns about.
  final currency = ref.read(currencyProvider).valueOrNull ?? defaultCurrency;
  final name = TextEditingController(text: existing?.name ?? '');
  final amount = TextEditingController(text: existing?.amount?.toStringAsFixed(0) ?? '');
  final source = TextEditingController(text: existing?.leadSource ?? '');
  final phone = TextEditingController(text: existing?.phone ?? '');
  final note = TextEditingController(text: existing?.note ?? '');
  final monthly = TextEditingController(text: existing?.monthly?.toStringAsFixed(0) ?? '');
  final deposit =
      TextEditingController(text: existing?.deposit?.toStringAsFixed(0) ?? '');
  var status = existing?.status ?? 'lead';
  // Two dates, each asked for in the words of the page it feeds: work goes to
  // the Tasks page, money goes to the Money page. The form used to ask for
  // invoiced-on plus net terms and work the payment date out, which was three
  // questions for one date and no place to say when the job itself is due.
  DateTime? paymentDue = existing?.parsedDue;
  DateTime? workDue;

  final saved = await showKoruSheet<bool>(
    context,
    title: existing == null ? 'New client' : 'Edit client',
    subtitle: existing == null
        ? 'Amounts are in ${currency.code}. The client lives on the Clients '
            'page, the work in Tasks, the money in Money.'
        : 'Changes are kept on this device.',
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheetState) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          KoruFieldStack(
            children: [
              TextField(
                controller: name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Name or company'),
              ),
              KoruFieldRow(
                flex: const [2, 3],
                children: [
                  TextField(
                    controller: amount,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Invoiced',
                      suffixText: currency.symbol,
                    ),
                  ),
                  DropdownButtonFormField<String>(
                    value: status,
                    decoration: const InputDecoration(labelText: 'What this is'),
                    items: kClientStatuses
                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                    onChanged: (v) => status = v ?? 'lead',
                  ),
                ],
              ),
              TextField(
                controller: monthly,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Monthly retainer',
                  suffixText: currency.symbol,
                  helperText: 'Only if they pay you the same amount every month.',
                ),
              ),
              TextField(
                controller: source,
                decoration: const InputDecoration(
                    labelText: 'Lead source', hintText: 'referral, twitter, ads...'),
              ),
              TextField(
                controller: phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Phone',
                  hintText: '07700 900123',
                  helperText: 'Used only to open WhatsApp when you tap follow up.',
                  helperMaxLines: 2,
                ),
              ),
              TextField(
                controller: note,
                maxLines: 2,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Note',
                  hintText: 'What was agreed?',
                ),
              ),
            ],
          ),
          const SizedBox(height: KoruSpace.xl),
          KoruFieldStack(
            children: [
              // The work date, named after where it lands. Picking one writes
              // a task called "Work for {name}", so a job agreed here shows up
              // in the list the user actually works from instead of living
              // only on the client row.
              KoruDateButton(
                label: 'Task due date',
                icon: Icons.task_alt_rounded,
                value: workDue == null ? 'no date' : readableDate(workDue!),
                tone: workDue == null ? null : KoruColors.leaf,
                onTap: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    firstDate: DateTime.now().subtract(const Duration(days: 365 * 2)),
                    lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
                    initialDate: workDue ?? DateTime.now(),
                    helpText: 'When does the work have to be done?',
                  );
                  if (picked != null) setSheetState(() => workDue = picked);
                },
              ),
              if (workDue != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setSheetState(() => workDue = null),
                    icon: const Icon(Icons.close_rounded, size: KoruSize.iconSm),
                    label: const Text('No task date'),
                  ),
                ),
              // The money date, named after the page that watches it. A plain
              // date rather than terms and a computed figure: one question, one
              // answer, and the answer is the date the rest of the app will use.
              KoruDateButton(
                label: 'Payment due date',
                icon: Icons.receipt_long_outlined,
                value: paymentDue == null ? 'no date' : readableDate(paymentDue!),
                tone: paymentDue == null ? null : KoruColors.leaf,
                onTap: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    firstDate: DateTime.now().subtract(const Duration(days: 365 * 2)),
                    lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
                    initialDate: paymentDue ?? DateTime.now(),
                    helpText: 'When does the payment have to arrive?',
                  );
                  if (picked != null) setSheetState(() => paymentDue = picked);
                },
              ),
              if (paymentDue != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setSheetState(() => paymentDue = null),
                    icon: const Icon(Icons.close_rounded, size: KoruSize.iconSm),
                    label: const Text('No payment date'),
                  ),
                ),
              TextField(
                controller: deposit,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Deposit already paid',
                  suffixText: currency.symbol,
                  helperText: 'Only if they paid something up front.',
                ),
              ),
            ],
          ),
          const SizedBox(height: KoruSpace.xl),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(existing == null ? 'Save client' : 'Save changes'),
          ),
        ],
      ),
    ),
  );

  if (saved == true && name.text.trim().isNotEmpty) {
    final store = await ref.read(storeProvider.future);
    final agreed = double.tryParse(amount.text.trim());

    // An agreed amount is required, not optional.
    //
    // Every total on this screen is agreed minus received, so a client saved
    // without one contributes zero to owed, zero to outstanding, and never
    // goes overdue. That is not an edge case, it was the normal outcome of
    // the old form, and it is why the Business page read zero across the
    // board and the notifications had nothing to ever say.
    if (agreed == null || agreed <= 0) {
      if (context.mounted) {
        toast(context, 'Put the amount you agreed with them');
      }
      return;
    }

    final depositValue = double.tryParse(deposit.text.trim()) ?? 0;
    final record = Client(
      id: existing?.id,
      name: name.text.trim(),
      status: status,
      amount: agreed,
      due: paymentDue == null ? null : isoDate(paymentDue!),
      leadSource: source.text.trim().isEmpty ? null : source.text.trim(),
      phone: phone.text.trim().isEmpty ? null : phone.text.trim(),
      note: note.text.trim().isEmpty ? null : note.text.trim(),
      created: existing?.created ?? DateTime.now().toIso8601String(),
      monthly: double.tryParse(monthly.text.trim()),
      deposit: depositValue > 0 ? depositValue : null,
      // No terms any more: the form asks for the date itself instead of
      // working it out from a net-days pick, so only the override path exists.
      termsDays: null,
      invoicedOn: existing?.invoicedOn ?? isoDate(DateTime.now()),
    );

    int? clientId;
    if (existing == null) {
      clientId = await store.addClient(record);
    } else {
      await store.updateClient(record);
      clientId = existing.id;
    }

    // The deposit goes into the ledger rather than being subtracted from the
    // amount. One place holds money: agreed minus received. A deposit held
    // only on the client row would be a second opinion, and the two would
    // disagree the first time somebody paid something else too.
    //
    // A new client only. Re-recording the same deposit on every edit would
    // count it again each time somebody fixed a typo in the name.
    if (existing == null && depositValue > 0 && clientId != null) {
      await store.addPayment(Payment(
        clientId: clientId,
        amount: depositValue,
        date: isoDate(DateTime.now()),
        note: 'Deposit',
      ));
    }

    // The task date becomes a real task, not a second date on the client row.
    // Work belongs in the list the user works from; the client page is the
    // record of what was agreed with whom. One open task per client, titled
    // after them, updated in place when the date moves.
    if (workDue != null && clientId != null) {
      final title = 'Work for ${record.name}';
      final open = await store.tasks(clientId: clientId, openOnly: true);
      Task? existingTask;
      for (final t in open) {
        if (t.clientId == clientId && t.title == title) {
          existingTask = t;
          break;
        }
      }
      final work = Task(
        id: existingTask?.id,
        title: title,
        clientId: clientId,
        due: isoDate(workDue!),
        created: existingTask?.created ?? DateTime.now().toIso8601String(),
        note: existingTask?.note,
      );
      if (existingTask == null) {
        await store.addTask(work);
      } else {
        await store.updateTask(work);
      }
    }

    invalidateWorkData(ref);
    if (context.mounted) {
      toast(context, existing == null ? 'Client added' : 'Client updated');
    }
  }
}

/// Records money arriving, in whole or in part.
///
/// This used to set the client's status to paid and overwrite the invoiced
/// amount with whatever was typed in, which silently destroyed the original
/// figure and could not express a part payment at all. It now appends to the
/// ledger and leaves the invoice alone; the status only moves to paid when
/// the balance actually reaches zero.
Future<void> recordPaymentSheet(
  BuildContext context,
  WidgetRef ref,
  Client c,
  double alreadyReceived,
) async {
  // Read synchronously: the sheet below is shown with this context, and
  // awaiting anything first is exactly what the linter is warning about.
  final currency = ref.read(currencyProvider).valueOrNull ?? defaultCurrency;
  final balance = c.balanceWith(alreadyReceived);

  // Defaults to what is outstanding, not to the invoice. Offering the full
  // invoice as the default made a second part payment pre-fill with the
  // original figure, which is exactly the number the user did not want.
  final controller = TextEditingController(
    text: balance > 0 ? balance.toStringAsFixed(0) : '',
  );
  final note = TextEditingController();
  var date = DateTime.now();

  final ok = await showKoruSheet<bool>(
    context,
    title: 'Payment from ${c.name}',
    subtitle: balance > 0
        ? '${money(balance)} ${currency.code} still outstanding of ${money(c.amount ?? 0)} invoiced.'
        : 'Nothing outstanding. Recording more will show as overpaid.',
    builder: (ctx) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KoruFieldStack(
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Amount received',
                suffixText: currency.symbol,
                helperText: 'Part payments are fine.',
              ),
            ),
            TextField(
              controller: note,
              decoration: const InputDecoration(
                  labelText: 'Note', hintText: 'Invoice 3, transfer, cash...'),
            ),
            KoruDateButton(
              label: 'Received',
              icon: Icons.event_outlined,
              value: readableDate(date),
              onTap: () async {
                final picked = await showDatePicker(
                  context: ctx,
                  firstDate: DateTime.now().subtract(const Duration(days: 365 * 3)),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                  initialDate: date,
                );
                if (picked != null) date = picked;
              },
            ),
          ],
        ),
        const SizedBox(height: KoruSpace.xl),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Record payment'),
        ),
      ],
    ),
  );
  if (ok != true) return;

  final amount = double.tryParse(controller.text.trim());
  // A blank or malformed box used to fall back to writing the invoice as
  // received. Silently inventing a payment is worse than refusing it.
  if (amount == null || amount <= 0) {
    if (context.mounted) toast(context, 'Enter an amount first');
    return;
  }

  final store = await ref.read(storeProvider.future);
  await store.addPayment(Payment(
    clientId: c.id!,
    amount: amount,
    date: isoDate(date),
    note: note.text.trim().isEmpty ? null : note.text.trim(),
  ));

  // Settles only when the ledger says it is settled. A lost client stays lost
  // even if a payment lands, because resurrecting it is not a payment's job.
  final settled = c.balanceWith(alreadyReceived + amount) <= 0;
  if (settled && c.status != 'paid' && c.status != 'lost') {
    await store.setClientStatus(c.id!, 'paid');
  }

  invalidateWorkData(ref);
  if (!context.mounted) return;
  // The one action in this app that is unambiguously good news, so it lands
  // like news: Koru cheers, the amount rises, the phone thumps. The toast
  // underneath still carries the number that matters — what is left.
  celebrateMoneyIn(
    context,
    amount: '+ ${money(amount)} ${currency.code}',
    caption: settled ? '${c.name} settled' : c.name,
  );
  final left = c.balanceWith(alreadyReceived + amount);
  toast(
    context,
    settled
        ? '${c.name} settled'
        : '${c.name}: ${money(left)} ${currency.code} still outstanding',
  );
}

/// Put something that has to happen on the list.
Future<void> addDeadlineSheet(
  BuildContext context,
  WidgetRef ref,
  List<Client> clients,
) async {
  final title = TextEditingController();
  Client? client;
  var date = DateTime.now().add(const Duration(days: 7));

  final ok = await showKoruSheet<bool>(
    context,
    title: 'New deadline',
    subtitle: 'Something that has to happen, on a date.',
    builder: (ctx) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KoruFieldStack(
          children: [
            TextField(
              controller: title,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                  labelText: 'What', hintText: 'Send invoice, deliver the site...'),
            ),
            if (clients.isNotEmpty)
              DropdownButtonFormField<Client>(
                decoration: const InputDecoration(labelText: 'For which client'),
                items: clients
                    .map((c) => DropdownMenuItem(value: c, child: Text(c.name)))
                    .toList(),
                onChanged: (v) => client = v,
              ),
            KoruDateButton(
              label: 'Due',
              icon: Icons.event_outlined,
              value: readableDate(date),
              onTap: () async {
                final picked = await showDatePicker(
                  context: ctx,
                  firstDate: DateTime.now().subtract(const Duration(days: 365)),
                  lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
                  initialDate: date,
                );
                if (picked != null) date = picked;
              },
            ),
          ],
        ),
        const SizedBox(height: KoruSpace.xl),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Add deadline'),
        ),
      ],
    ),
  );

  if (ok != true || title.text.trim().isEmpty) return;
  final store = await ref.read(storeProvider.future);
  await store.addDeadline(Deadline(
    clientId: client?.id,
    title: title.text.trim(),
    due: isoDate(date),
  ));
  invalidateWorkData(ref);
  if (context.mounted) toast(context, 'Deadline added');
}
