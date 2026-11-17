import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await store.init(); // abre o banco SQLite e carrega os dados
  runApp(const CarecasApp());
}

const kBg = Color(0xFF222222);
const kOrange = Color(0xFFFF7A00);
const kField = Color(0xFFDDDDDD);
const kRed = Color(0xFFB00000);
const kSlots = ['09:00', '10:00', '11:00', '13:00', '14:00', '15:00', '16:00', '17:00'];

DateTime dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);
String fmtDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

// ───────────────────────── MODELOS + ESTADO ─────────────────────────

class Barber {
  final String id, name;
  final Color color;
  final String? photo; // ex.: 'assets/davy.png' (se null, usa o avatar padrão)
  const Barber(this.id, this.name, this.color, {this.photo});
}

class Appointment {
  final int id;
  final String client, phone, barberId, slot;
  final DateTime date;
  Appointment(this.id, this.client, this.phone, this.barberId, this.date, this.slot);
}

class Store extends ChangeNotifier {
  static final instance = Store._();
  Store._();

  late Database db;

  String _iso(DateTime d) => d.toIso8601String().substring(0, 10);

  Future<void> init() async {
    db = await openDatabase(
      '${await getDatabasesPath()}/carecas.db',
      version: 1,
      onCreate: (d, _) async {
        await d.execute(
            'CREATE TABLE availability(barber_id TEXT, date TEXT, PRIMARY KEY(barber_id, date))');
        await d.execute('CREATE TABLE appointments('
            'id INTEGER PRIMARY KEY AUTOINCREMENT, client TEXT, phone TEXT, '
            'barber_id TEXT, date TEXT, slot TEXT)');
        // dados de exemplo (só na primeira execução)
        final today = dayOnly(DateTime.now());
        final batch = d.batch();
        for (final id in ['davy', 'david']) {
          for (var i = 0; i < 21; i++) {
            final day = today.add(Duration(days: i));
            if (day.weekday != DateTime.sunday) {
              batch.insert('availability', {'barber_id': id, 'date': _iso(day)});
            }
          }
        }
        await batch.commit(noResult: true);
      },
    );
    for (final r in await db.query('availability')) {
      availability
          .putIfAbsent(r['barber_id'] as String, () => {})
          .add(DateTime.parse(r['date'] as String));
    }
    appointments
      ..clear()
      ..addAll((await db.query('appointments')).map((r) => Appointment(
          r['id'] as int,
          r['client'] as String,
          r['phone'] as String,
          r['barber_id'] as String,
          DateTime.parse(r['date'] as String),
          r['slot'] as String)));
  }

  final barbers = const [
    Barber('davy', 'Davy', Color(0xFFFF69B4)),
    Barber('david', 'David', Color(0xFF2962FF)),
    Barber('renan', 'Renan', Color(0xFFE53935)),
  ];
  final Map<String, Set<DateTime>> availability = {};
  final List<Appointment> appointments = [];
  String clientName = '', clientPhone = '';

  Barber barberById(String id) => barbers.firstWhere((b) => b.id == id);

  bool isAvailable(String b, DateTime d) => availability[b]?.contains(dayOnly(d)) ?? false;

  bool hasFuture(String b) {
    final t = dayOnly(DateTime.now());
    return availability[b]?.any((d) => !d.isBefore(t)) ?? false;
  }

  /// Marca/desmarca disponibilidade. Retorna false se já há agendamento no dia.
  bool toggle(String b, DateTime d) {
    d = dayOnly(d);
    final set = availability.putIfAbsent(b, () => {});
    if (set.contains(d)) {
      if (appointments.any((a) => a.barberId == b && a.date == d)) return false;
      set.remove(d);
      db.delete('availability', where: 'barber_id=? AND date=?', whereArgs: [b, _iso(d)]);
    } else {
      set.add(d);
      db.insert('availability', {'barber_id': b, 'date': _iso(d)});
    }
    notifyListeners();
    return true;
  }

  List<String> freeSlots(String b, DateTime d, {int? ignoreId}) => kSlots
      .where((s) => !appointments.any(
          (a) => a.barberId == b && a.date == dayOnly(d) && a.slot == s && a.id != ignoreId))
      .toList();

  Future<void> book(Barber b, DateTime d, String slot, {int? replaceId}) async {
    if (replaceId != null) {
      await db.delete('appointments', where: 'id=?', whereArgs: [replaceId]);
      appointments.removeWhere((a) => a.id == replaceId);
    }
    final id = await db.insert('appointments', {
      'client': clientName,
      'phone': clientPhone,
      'barber_id': b.id,
      'date': _iso(d),
      'slot': slot,
    });
    appointments.add(Appointment(id, clientName, clientPhone, b.id, dayOnly(d), slot));
    notifyListeners();
  }

  Future<void> cancel(int id) async {
    await db.delete('appointments', where: 'id=?', whereArgs: [id]);
    appointments.removeWhere((a) => a.id == id);
    notifyListeners();
  }

  List<Appointment> mine() => appointments
      .where((a) => a.client == clientName && a.phone == clientPhone)
      .toList()
    ..sort((a, b) => a.date.compareTo(b.date));
}

final store = Store.instance;

// ───────────────────────── APP + WIDGETS BASE ─────────────────────────

class CarecasApp extends StatelessWidget {
  const CarecasApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: "Careca's Barber",
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: kBg,
      colorScheme: const ColorScheme.dark(primary: kOrange, surface: kBg),
    ),
    home: const RoleScreen(),
  );
}

class Logo extends StatelessWidget {
  const Logo({super.key});
  @override
  Widget build(BuildContext context) => const Column(children: [
    Icon(Icons.content_cut, color: kOrange, size: 32),
    Text("Careca's",
        style: TextStyle(color: kOrange, fontSize: 30, fontWeight: FontWeight.w900)),
    Text('BARBER', style: TextStyle(color: kOrange, fontSize: 11, letterSpacing: 4)),
  ]);
}

class Frame extends StatelessWidget {
  final String? title;
  final Widget child;
  final bool boxed;
  const Frame({super.key, required this.child, this.title, this.boxed = false});

  @override
  Widget build(BuildContext context) {
    Widget body = Column(children: [
      if (title != null) ...[
        Text(title!,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Colors.white)),
        const SizedBox(height: 14),
      ],
      child,
    ]);
    if (boxed) {
      body = Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
            border: Border.all(color: kOrange, width: 2), borderRadius: BorderRadius.circular(20)),
        child: body,
      );
    }
    return Scaffold(
      body: SafeArea(
        child: Stack(children: [
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(children: [const Logo(), const SizedBox(height: 18), body]),
              ),
            ),
          ),
          if (Navigator.canPop(context))
            Positioned(
              left: 4,
              top: 4,
              child: IconButton(
                  icon: const Icon(Icons.reply, color: kOrange, size: 30),
                  onPressed: () => Navigator.pop(context)),
            ),
        ]),
      ),
    );
  }
}

class OrangeButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final Color color;
  const OrangeButton(this.text, this.onPressed, {super.key, this.color = kOrange});
  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    height: 52,
    child: ElevatedButton(
      style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: color == kOrange ? Colors.black : Colors.white,
          disabledBackgroundColor: Colors.white12,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
      onPressed: onPressed,
      child: Text(text,
          textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800)),
    ),
  );
}

class PickField extends StatelessWidget {
  final IconData icon;
  final String label, text;
  final VoidCallback? onTap;
  const PickField(this.icon, this.label, this.text, this.onTap, {super.key});
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
    const SizedBox(height: 4),
    Row(children: [
      Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(6)),
          child: Icon(icon, color: kOrange, size: 20)),
      const SizedBox(width: 8),
      Expanded(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(color: kField, borderRadius: BorderRadius.circular(20)),
            child: Row(children: [
              Expanded(
                  child: Text(text,
                      style: const TextStyle(
                          color: Colors.black, fontWeight: FontWeight.w600, fontSize: 13))),
              if (onTap != null) const Icon(Icons.arrow_drop_down, color: Colors.black54),
            ]),
          ),
        ),
      ),
    ]),
  ]);
}

class BarberAvatar extends StatelessWidget {
  final Barber barber;
  final double size;
  const BarberAvatar(this.barber, {super.key, this.size = 56});
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: const Color(0xFF555555), borderRadius: BorderRadius.circular(14)),
    clipBehavior: Clip.antiAlias,
    child: barber.photo != null
        ? Image.asset(barber.photo!, fit: BoxFit.cover)
        : Stack(alignment: Alignment.center, children: [
      Icon(Icons.person, size: size * 0.85, color: Colors.black54),
      Positioned(
        top: size * 0.58,
        child: Container(
            width: size * 0.42,
            height: size * 0.1,
            decoration: BoxDecoration(
                color: barber.color, borderRadius: BorderRadius.circular(8))),
      ),
    ]),
  );
}

void snack(BuildContext c, String msg) => ScaffoldMessenger.of(c)
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(msg)));

// ───────────────────────── LOGIN ─────────────────────────

class RoleScreen extends StatelessWidget {
  const RoleScreen({super.key});
  @override
  Widget build(BuildContext context) => Frame(
    boxed: true,
    title: 'Login',
    child: Column(children: [
      const Text('Entrar como:', style: TextStyle(color: Colors.white70)),
      const SizedBox(height: 20),
      for (final isClient in [true, false]) ...[
        SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: kField,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => LoginScreen(isClient: isClient))),
            child: Text(isClient ? 'CLIENTE' : 'BARBEIRO',
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
          ),
        ),
        const SizedBox(height: 16),
      ],
    ]),
  );
}

class LoginScreen extends StatefulWidget {
  final bool isClient;
  const LoginScreen({super.key, required this.isClient});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final name = TextEditingController(), phone = TextEditingController();
  bool keep = false, whats = false;

  InputDecoration _dec() => InputDecoration(
      filled: true,
      fillColor: kField,
      isDense: true,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none));

  void _enter() {
    if (name.text.trim().isEmpty || phone.text.trim().length < 10) {
      snack(context, 'Informe seu nome e um número com DDD.');
      return;
    }
    store.clientName = name.text.trim();
    store.clientPhone = phone.text.trim();
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const ClientHome()));
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isClient) {
      return Frame(
        boxed: true,
        title: 'Quem é você?',
        child: Column(children: [
          for (final b in store.barbers)
            ListTile(
              leading: BarberAvatar(b),
              title: Text(b.name, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
              onTap: () => Navigator.pushReplacement(
                  context, MaterialPageRoute(builder: (_) => BarberHome(barber: b))),
            ),
        ]),
      );
    }
    return Frame(
      boxed: true,
      title: 'Login',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Digite seu nome:', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        TextField(controller: name, style: const TextStyle(color: Colors.black), decoration: _dec()),
        const SizedBox(height: 14),
        const Text('Número:', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        TextField(
            controller: phone,
            keyboardType: TextInputType.phone,
            style: const TextStyle(color: Colors.black),
            decoration: _dec()),
        Align(
          alignment: Alignment.centerRight,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Text('Manter-me conectado', style: TextStyle(fontSize: 12)),
            Switch(value: keep, activeThumbColor: kOrange, onChanged: (v) => setState(() => keep = v)),
          ]),
        ),
        OrangeButton('Iniciar\nAgendamento', _enter),
        Row(children: [
          Checkbox(value: whats, activeColor: kOrange, onChanged: (v) => setState(() => whats = v!)),
          const Expanded(
              child: Text('Autorizo mensagens via WhatsApp', style: TextStyle(fontSize: 12))),
        ]),
        const Text(
            'Ao selecionar esta opção você está autorizando o acesso ao número de WhatsApp, usamos seu número apenas para enviar confirmações, lembretes e facilitar seus agendamentos.',
            style: TextStyle(fontSize: 10, color: Colors.white54)),
      ]),
    );
  }
}

// ───────────────────────── ÁREA DO CLIENTE ─────────────────────────

class ClientHome extends StatelessWidget {
  const ClientHome({super.key});
  @override
  Widget build(BuildContext context) => Frame(
    boxed: true,
    title: 'ÁREA DO CLIENTE',
    child: Column(children: [
      const SizedBox(height: 16),
      OrangeButton('Realizar um\nAGENDAMENTO',
              () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BookScreen()))),
      const SizedBox(height: 28),
      OrangeButton('VISUALIZAR\nAGENDAMENTOS',
              () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MyAppointments()))),
      const SizedBox(height: 16),
    ]),
  );
}

class BookScreen extends StatefulWidget {
  final Appointment? editing;
  const BookScreen({super.key, this.editing});
  @override
  State<BookScreen> createState() => _BookScreenState();
}

class _BookScreenState extends State<BookScreen> {
  Barber? barber;
  DateTime? date;
  String? slot;

  @override
  void initState() {
    super.initState();
    final e = widget.editing;
    if (e != null) {
      barber = store.barberById(e.barberId);
      date = e.date;
      slot = e.slot;
    }
  }

  Future<void> _pickBarber() async {
    final b = await showModalBottomSheet<Barber>(
      context: context,
      backgroundColor: kBg,
      builder: (_) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Barbeiros', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
          for (final b in store.barbers)
            ListTile(
              enabled: store.hasFuture(b.id),
              leading: Opacity(opacity: store.hasFuture(b.id) ? 1 : 0.35, child: BarberAvatar(b)),
              title: Text(b.name, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
              subtitle: Text(store.hasFuture(b.id) ? 'Agenda aberta' : 'Sem datas disponíveis'),
              onTap: () => Navigator.pop(context, b),
            ),
        ]),
      ),
    );
    if (b == null) return;
    setState(() {
      barber = b;
      if (date != null && !store.isAvailable(b.id, date!)) {
        date = null;
        slot = null;
      }
    });
  }

  Future<void> _pickDate() async {
    if (barber == null) return snack(context, 'Selecione o barbeiro primeiro.');
    final today = dayOnly(DateTime.now());
    final avail = (store.availability[barber!.id] ?? {}).where((d) => !d.isBefore(today)).toList()
      ..sort();
    if (avail.isEmpty) return snack(context, 'Este barbeiro não tem datas disponíveis.');
    final initial = (date != null && avail.contains(date)) ? date! : avail.first;
    final d = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: today,
      lastDate: avail.last,
      helpText: 'Datas disponíveis de ${barber!.name}',
      selectableDayPredicate: (x) => store.isAvailable(barber!.id, x),
    );
    if (d != null) {
      setState(() {
        date = dayOnly(d);
        slot = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final free = (barber != null && date != null)
        ? store.freeSlots(barber!.id, date!, ignoreId: widget.editing?.id)
        : <String>[];
    return Frame(
      title: widget.editing == null ? 'Agende um atendimento' : 'Alterar agendamento',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Selecione barbeiro, data e horário para criar o agendamento.',
            textAlign: TextAlign.center, style: TextStyle(color: Colors.white54)),
        const SizedBox(height: 20),
        PickField(Icons.person_outline, 'Barbeiro', barber?.name ?? 'Clique para selecionar o barbeiro',
            _pickBarber),
        if (barber != null)
          Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(children: [BarberAvatar(barber!, size: 44), const SizedBox(width: 12), Text(barber!.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800))])),
        const SizedBox(height: 16),
        PickField(Icons.calendar_month, 'Data',
            date == null ? 'Clique para selecionar a data' : fmtDate(date!), _pickDate),
        if (date != null) ...[
          const SizedBox(height: 16),
          const Text('Horário', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 8),
          if (free.isEmpty)
            const Text('Sem horários livres nesta data.', style: TextStyle(color: Colors.white54))
          else
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final s in free)
                ChoiceChip(
                  label: Text(s),
                  selected: slot == s,
                  selectedColor: kOrange,
                  labelStyle: TextStyle(color: slot == s ? Colors.black : Colors.white),
                  onSelected: (_) => setState(() => slot = s),
                ),
            ]),
        ],
        const SizedBox(height: 28),
        OrangeButton(
          'Ver Resumo do Agendamento',
          (barber != null && date != null && slot != null && free.contains(slot))
              ? () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => SummaryScreen(
                      barber: barber!, date: date!, slot: slot!, editing: widget.editing)))
              : null,
        ),
      ]),
    );
  }
}

class SummaryScreen extends StatelessWidget {
  final Barber barber;
  final DateTime date;
  final String slot;
  final Appointment? editing;
  const SummaryScreen(
      {super.key, required this.barber, required this.date, required this.slot, this.editing});

  @override
  Widget build(BuildContext context) => Frame(
    title: 'Resumo de Agendamento',
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 10),
      PickField(Icons.person_outline, 'Barbeiro', barber.name, null),
      const SizedBox(height: 18),
      PickField(Icons.calendar_month, 'Data', fmtDate(date), null),
      const SizedBox(height: 18),
      PickField(Icons.schedule, 'Horário', slot, null),
      const SizedBox(height: 36),
      OrangeButton('Agendar', () async {
        if (!store.freeSlots(barber.id, date, ignoreId: editing?.id).contains(slot)) {
          snack(context, 'Esse horário acabou de ser ocupado. Escolha outro.');
          return;
        }
        await store.book(barber, date, slot, replaceId: editing?.id);
        if (!context.mounted) return;
        Navigator.pushAndRemoveUntil(
            context, MaterialPageRoute(builder: (_) => const SuccessScreen()), (r) => r.isFirst);
      }),
    ]),
  );
}

class SuccessScreen extends StatelessWidget {
  const SuccessScreen({super.key});
  @override
  Widget build(BuildContext context) => Frame(
    child: Column(children: [
      const SizedBox(height: 60),
      const Icon(Icons.check_circle, color: kOrange, size: 72),
      const SizedBox(height: 16),
      const Text('Agendamento Realizado\ncom Sucesso!',
          textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
      const SizedBox(height: 50),
      OrangeButton(
          'Voltar para Menu',
              () => Navigator.pushAndRemoveUntil(
              context, MaterialPageRoute(builder: (_) => const ClientHome()), (r) => r.isFirst),
          color: kRed),
    ]),
  );
}

class MyAppointments extends StatelessWidget {
  const MyAppointments({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final list = store.mine();
      return Frame(
        title: 'MEUS HORÁRIOS\nMARCADOS',
        child: list.isEmpty
            ? const Padding(
            padding: EdgeInsets.only(top: 40),
            child: Text('Você ainda não tem agendamentos.', style: TextStyle(color: Colors.white54)))
            : Column(children: [
          for (final a in list)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  border: Border.all(color: kOrange, width: 2),
                  borderRadius: BorderRadius.circular(16)),
              child: Column(children: [
                Row(children: [
                  const Icon(Icons.calendar_month, color: kOrange),
                  const SizedBox(width: 10),
                  Text('${fmtDate(a.date)} às ${a.slot}',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  BarberAvatar(store.barberById(a.barberId), size: 36),
                  const SizedBox(width: 10),
                  Text(store.barberById(a.barberId).name,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
                ]),
                const SizedBox(height: 14),
                OrangeButton(
                    'ALTERAR DATA OU PROFISSIONAL',
                        () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => BookScreen(editing: a)))),
                const SizedBox(height: 8),
                OrangeButton(
                    'COMPARTILHAR COMPROVANTE',
                        () => Share.share(
                        "✂️ Careca's Barber\nAgendamento confirmado!\n"
                            'Barbeiro: ${store.barberById(a.barberId).name}\n'
                            'Data: ${fmtDate(a.date)}\nHorário: ${a.slot}',
                        subject: "Agendamento - Careca's Barber"),
                    color: const Color(0xFF444444)),
                const SizedBox(height: 8),
                OrangeButton('DESMARCAR AGENDAMENTO', () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('Desmarcar?'),
                      content: Text('Cancelar o horário de ${fmtDate(a.date)} às ${a.slot}?'),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Voltar')),
                        TextButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Desmarcar')),
                      ],
                    ),
                  );
                  if (ok == true) store.cancel(a.id);
                }, color: kRed),
              ]),
            ),
        ]),
      );
    },
  );
}

// ───────────────────────── ÁREA DO BARBEIRO ─────────────────────────

class BarberHome extends StatelessWidget {
  final Barber barber;
  const BarberHome({super.key, required this.barber});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final mine = store.appointments.where((a) => a.barberId == barber.id).toList()
        ..sort((a, b) {
          final c = a.date.compareTo(b.date);
          return c != 0 ? c : a.slot.compareTo(b.slot);
        });
      return Frame(
        title: 'ÁREA DO BARBEIRO',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            BarberAvatar(barber, size: 48),
            const SizedBox(width: 12),
            Text(barber.name, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 16),
          const Text('Toque nos dias em que você vai atender (laranja = disponível):',
              style: TextStyle(color: Colors.white70)),
          const SizedBox(height: 8),
          AvailabilityCalendar(
            selected: store.availability[barber.id] ?? {},
            onTap: (d) {
              if (!store.toggle(barber.id, d)) {
                snack(context, 'Já existe cliente agendado nesse dia.');
              }
            },
          ),
          const SizedBox(height: 20),
          const Text('Clientes agendados',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          if (mine.isEmpty)
            const Text('Nenhum agendamento ainda.', style: TextStyle(color: Colors.white54)),
          for (final a in mine)
            ListTile(
              dense: true,
              leading: const Icon(Icons.event, color: kOrange),
              title: Text('${fmtDate(a.date)} às ${a.slot}'),
              subtitle: Text('${a.client} • ${a.phone}'),
            ),
        ]),
      );
    },
  );
}

class AvailabilityCalendar extends StatefulWidget {
  final Set<DateTime> selected;
  final void Function(DateTime) onTap;
  const AvailabilityCalendar({super.key, required this.selected, required this.onTap});
  @override
  State<AvailabilityCalendar> createState() => _AvailabilityCalendarState();
}

class _AvailabilityCalendarState extends State<AvailabilityCalendar> {
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);
  static const names = [
    'Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho',
    'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro'
  ];

  @override
  Widget build(BuildContext context) {
    final today = dayOnly(DateTime.now());
    final offset = DateTime(month.year, month.month, 1).weekday % 7;
    final total = DateTime(month.year, month.month + 1, 0).day;
    return Column(children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () => setState(() => month = DateTime(month.year, month.month - 1))),
        Text('${names[month.month - 1]} ${month.year}',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: () => setState(() => month = DateTime(month.year, month.month + 1))),
      ]),
      Row(children: [
        for (final w in ['D', 'S', 'T', 'Q', 'Q', 'S', 'S'])
          Expanded(child: Center(child: Text(w, style: const TextStyle(color: Colors.white54)))),
      ]),
      GridView.count(
        crossAxisCount: 7,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          for (var i = 0; i < offset; i++) const SizedBox(),
          for (var d = 1; d <= total; d++) _cell(DateTime(month.year, month.month, d), today),
        ],
      ),
    ]);
  }

  Widget _cell(DateTime day, DateTime today) {
    final past = day.isBefore(today);
    final sel = widget.selected.contains(day);
    return GestureDetector(
      onTap: past ? null : () => widget.onTap(day),
      child: Container(
        margin: const EdgeInsets.all(3),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: sel ? kOrange : null,
          shape: BoxShape.circle,
          border: day == today ? Border.all(color: kOrange) : null,
        ),
        child: Text('${day.day}',
            style: TextStyle(
                fontWeight: FontWeight.w700,
                color: past ? Colors.white24 : (sel ? Colors.black : Colors.white))),
      ),
    );
  }
}
