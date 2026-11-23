import 'package:material_ui/material_ui.dart';

const accent = Color(0xffdbff46);
const canvasColor = Color(0xff0c1516);
const panelColor = Color(0xff172425);
const borderColor = Color(0xff304142);
const inkColor = Color(0xffeff6eb);
const secondaryText = Color(0xffb0c2bb);

class PursuitScreen extends StatelessWidget {
  const PursuitScreen({
    super.key,
    required this.title,
    required this.body,
    this.leading,
    this.actions,
  });

  final String title;
  final Widget body;
  final Widget? leading;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title), leading: leading, actions: actions),
    body: SafeArea(top: false, child: body),
  );
}

class ScreenList extends StatelessWidget {
  const ScreenList({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 640),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
        children: children,
      ),
    ),
  );
}

class PursuitCard extends StatelessWidget {
  const PursuitCard({super.key, required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Card(
    color: Theme.of(context).colorScheme.surface,
    elevation: 0,
    margin: EdgeInsets.zero,
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(
      side: const BorderSide(color: borderColor),
      borderRadius: BorderRadius.circular(22),
    ),
    child: onTap == null ? child : InkWell(onTap: onTap, child: child),
  );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.action});

  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 10),
    child: Row(
      children: [
        Expanded(
          child: Semantics(
            header: true,
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
        ),
        ?action,
      ],
    ),
  );
}

class DetailEditor extends StatefulWidget {
  const DetailEditor({
    super.key,
    required this.title,
    required this.values,
    this.requiredFields = const {},
    this.saveLabel = 'Save',
  });

  final String title;
  final Map<String, String> values;
  final Set<String> requiredFields;
  final String saveLabel;

  @override
  State<DetailEditor> createState() => _DetailEditorState();
}

class _DetailEditorState extends State<DetailEditor> {
  final _form = GlobalKey<FormState>();
  final _draft = <String, String>{};

  @override
  Widget build(BuildContext context) => PursuitScreen(
    title: widget.title,
    body: Form(
      key: _form,
      child: ScreenList(
        children: [
          for (final MapEntry(:key, :value) in widget.values.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TextFormField(
                initialValue: value,
                maxLength: 60,
                decoration: InputDecoration(labelText: key, counterText: ''),
                validator: (value) =>
                    widget.requiredFields.contains(key) && value!.trim().isEmpty
                    ? 'Enter ${key.toLowerCase()}.'
                    : null,
                onSaved: (value) => _draft[key] = value!.trim(),
              ),
            ),
          FilledButton(
            onPressed: () {
              final form = _form.currentState!;
              if (!form.validate()) return;
              form.save();
              Navigator.pop(context, _draft);
            },
            child: Text(widget.saveLabel),
          ),
        ],
      ),
    ),
  );
}

Future<String?> askForText(BuildContext context, String title, String label) {
  var draft = '';
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        autofocus: true,
        maxLength: 60,
        decoration: InputDecoration(labelText: label),
        onChanged: (value) => draft = value,
        onSubmitted: (value) => Navigator.pop(context, value.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, draft.trim()),
          child: const Text('Add'),
        ),
      ],
    ),
  );
}
