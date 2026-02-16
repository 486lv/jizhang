import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;  // 加上 "as p"
// import 'package:path/path.dart';
import 'package:intl/intl.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '老爸记账 v15.1 (Flutter版)',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2979FF)),
        scaffoldBackgroundColor: const Color(0xFFF2F2F7),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          titleTextStyle: TextStyle(color: Colors.black, fontSize: 20, fontWeight: FontWeight.bold),
          iconTheme: IconThemeData(color: Colors.black),
        ),
      ),
      home: const MainScreen(),
    );
  }
}

// ================== 1. 数据库管理类 ==================

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('dad_ledger_v15.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, filePath);
    return await openDatabase(path, version: 1, onCreate: _createDB);
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
    CREATE TABLE records (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      item_name TEXT,
      amount REAL,
      record_type INTEGER,
      date TEXT
    )
    ''');

    await db.execute('''
    CREATE TABLE debts (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      boss_name TEXT,
      amount REAL,
      note TEXT,
      date TEXT
    )
    ''');
  }

  // --- Records CRUD ---
  Future<int> addRecord(String name, double amount, int type, String date) async {
    final db = await instance.database;
    return await db.insert('records', {
      'item_name': name,
      'amount': amount,
      'record_type': type,
      'date': date,
    });
  }

  Future<List<Map<String, dynamic>>> getRecords({String? monthFilter}) async {
    final db = await instance.database;
    if (monthFilter != null) {
      return await db.query('records', where: 'date LIKE ?', whereArgs: ['$monthFilter%'], orderBy: 'date DESC, id DESC');
    }
    return await db.query('records', orderBy: 'date DESC, id DESC');
  }

  Future<int> deleteRecord(int id) async {
    final db = await instance.database;
    return await db.delete('records', where: 'id = ?', whereArgs: [id]);
  }

  // --- Debts CRUD ---
  Future<int> addDebt(String bossName, double amount, String note, String date) async {
    final db = await instance.database;
    return await db.insert('debts', {
      'boss_name': bossName,
      'amount': amount,
      'note': note,
      'date': date,
    });
  }

  Future<List<Map<String, dynamic>>> getDebts() async {
    final db = await instance.database;
    return await db.query('debts', orderBy: 'date DESC, id DESC');
  }

  Future<int> deleteDebt(int id) async {
    final db = await instance.database;
    return await db.delete('debts', where: 'id = ?', whereArgs: [id]);
  }

  // --- Stats ---
  Future<Map<String, double>> getMonthSummary(String monthStr) async {
    final db = await instance.database;
    final incRes = await db.rawQuery("SELECT SUM(amount) as t FROM records WHERE record_type = 1 AND date LIKE '$monthStr%'");
    final expRes = await db.rawQuery("SELECT SUM(amount) as t FROM records WHERE record_type = 0 AND date LIKE '$monthStr%'");

    double inc = (incRes.first['t'] as num?)?.toDouble() ?? 0.0;
    double exp = (expRes.first['t'] as num?)?.toDouble() ?? 0.0;
    return {'income': inc, 'expense': exp};
  }
}

// ================== 2. 主框架 (底部导航) ==================

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  final List<Widget> _pages = [
    const HomePage(),
    const StatsPage(),
    const DebtsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: _pages), // 保持页面状态
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (idx) => setState(() => _selectedIndex = idx),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: '记账'),
          NavigationDestination(icon: Icon(Icons.calendar_month_outlined), selectedIcon: Icon(Icons.calendar_month), label: '统计'),
          NavigationDestination(icon: Icon(Icons.account_balance_wallet_outlined), selectedIcon: Icon(Icons.account_balance_wallet), label: '欠款'),
        ],
      ),
    );
  }
}

// ================== 3. 首页 (记账) ==================

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<Map<String, dynamic>> _list = [];
  double _income = 0;
  double _expense = 0;
  String _filterType = 'all'; // all, income, expense

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  // 这里的 setState 用于刷新界面
  Future<void> _loadData() async {
    final now = DateTime.now();
    final monthStr = DateFormat('yyyy-MM').format(now);

    final allRecords = await DatabaseHelper.instance.getRecords(); // 获取所有记录
    final summary = await DatabaseHelper.instance.getMonthSummary(monthStr);

    setState(() {
      _list = allRecords;
      _income = summary['income']!;
      _expense = summary['expense']!;
    });
  }

  List<Map<String, dynamic>> get _filteredList {
    if (_filterType == 'income') return _list.where((e) => e['record_type'] == 1).toList();
    if (_filterType == 'expense') return _list.where((e) => e['record_type'] == 0).toList();
    return _list;
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final dateStr = "${now.year}年${now.month}月${now.day}日";

    return Scaffold(
      appBar: AppBar(title: Text("$dateStr 老爸记账")),
      body: Column(
        children: [
          // 概览卡片
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: const Offset(0, 4))]),
            child: Column(
              children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text("本月结余", style: TextStyle(color: Colors.grey)),
                  Text("¥${(_income - _expense).toStringAsFixed(0)}", style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                ]),
                const Divider(height: 30),
                Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                  _summaryItem("收入", _income, Colors.green),
                  Container(width: 1, height: 30, color: Colors.grey[300]),
                  _summaryItem("支出", _expense, Colors.red),
                ])
              ],
            ),
          ),
          // 筛选按钮
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _filterBtn("全部", 'all'),
              const SizedBox(width: 10),
              _filterBtn("收入", 'income', color: Colors.green),
              const SizedBox(width: 10),
              _filterBtn("支出", 'expense', color: Colors.red),
            ],
          ),
          const SizedBox(height: 10),
          // 列表
          Expanded(
            child: _filteredList.isEmpty
                ? Center(child: Text("暂无记录", style: TextStyle(color: Colors.grey[400])))
                : ListView.builder(
              itemCount: _filteredList.length,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemBuilder: (ctx, i) {
                final item = _filteredList[i];
                final isInc = item['record_type'] == 1;
                return Card(
                  elevation: 0,
                  color: Colors.white,
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: isInc ? Colors.green[50] : Colors.red[50],
                      child: Icon(isInc ? Icons.add : Icons.remove, color: isInc ? Colors.green : Colors.red),
                    ),
                    title: Text(item['item_name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(item['date'], style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text("${isInc ? '+' : '-'}¥${item['amount'].toStringAsFixed(0)}",
                            style: TextStyle(color: isInc ? Colors.green : Colors.red, fontWeight: FontWeight.bold, fontSize: 16)),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 20, color: Colors.grey),
                          onPressed: () async {
                            await DatabaseHelper.instance.deleteRecord(item['id']);
                            _loadData();
                          },
                        )
                      ],
                    ),
                  ),
                );
              },
            ),
          )
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddDialog(context),
        label: const Text("记一笔"),
        icon: const Icon(Icons.edit),
      ),
    );
  }

  Widget _summaryItem(String label, double val, Color color) {
    return Column(children: [Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)), Text("¥${val.toStringAsFixed(0)}", style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16))]);
  }

  Widget _filterBtn(String label, String key, {Color color = Colors.blue}) {
    final isSel = _filterType == key;
    return ChoiceChip(
      label: Text(label, style: TextStyle(color: isSel ? Colors.white : Colors.black)),
      selected: isSel,
      selectedColor: color,
      onSelected: (v) => setState(() => _filterType = key),
    );
  }

  void _showAddDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    final amtCtrl = TextEditingController();
    int type = 0; // 0 exp, 1 inc

    showModalBottomSheet(
        context: context, isScrollControlled: true,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setModalState) => Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom + 20, top: 20, left: 20, right: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("记一笔", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 15),
                Row(children: [
                  Expanded(child: ChoiceChip(label: const Center(child: Text("支出")), selected: type == 0, onSelected: (v) => setModalState(() => type = 0), selectedColor: Colors.red[100])),
                  const SizedBox(width: 10),
                  Expanded(child: ChoiceChip(label: const Center(child: Text("收入")), selected: type == 1, onSelected: (v) => setModalState(() => type = 1), selectedColor: Colors.green[100])),
                ]),
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: "干啥了？"), autofocus: true),
                TextField(controller: amtCtrl, decoration: const InputDecoration(labelText: "多少钱？", prefixText: "¥ "), keyboardType: TextInputType.number),
                const SizedBox(height: 20),
                SizedBox(width: double.infinity, child: ElevatedButton(
                  onPressed: () async {
                    if (nameCtrl.text.isEmpty || amtCtrl.text.isEmpty) return;
                    await DatabaseHelper.instance.addRecord(nameCtrl.text, double.parse(amtCtrl.text), type, DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now()));
                    if (mounted) { Navigator.pop(ctx); _loadData(); }
                  },
                  child: const Text("保存"),
                ))
              ],
            ),
          ),
        )
    );
  }
}

// ================== 4. 统计 (简单日历视图) ==================

class StatsPage extends StatefulWidget {
  const StatsPage({super.key});
  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  DateTime _currentMonth = DateTime.now();
  List<Map<String, dynamic>> _monthRecords = [];
  Map<int, double> _dailyInc = {};
  Map<int, double> _dailyExp = {};

  @override
  void initState() {
    super.initState();
    _loadMonthData();
  }

  Future<void> _loadMonthData() async {
    final monthStr = DateFormat('yyyy-MM').format(_currentMonth);
    final data = await DatabaseHelper.instance.getRecords(monthFilter: monthStr);

    Map<int, double> dInc = {};
    Map<int, double> dExp = {};

    for (var r in data) {
      // 解析日期 '2026-02-15 10:00'
      final day = int.parse(r['date'].toString().split(' ')[0].split('-')[2]);
      final amt = r['amount'] as double;
      if (r['record_type'] == 1) {
        dInc[day] = (dInc[day] ?? 0) + amt;
      } else {
        dExp[day] = (dExp[day] ?? 0) + amt;
      }
    }

    setState(() {
      _monthRecords = data;
      _dailyInc = dInc;
      _dailyExp = dExp;
    });
  }

  void _changeMonth(int delta) {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + delta, 1);
    });
    _loadMonthData();
  }

  @override
  Widget build(BuildContext context) {
    final daysInMonth = DateUtils.getDaysInMonth(_currentMonth.year, _currentMonth.month);
    final firstWeekday = DateTime(_currentMonth.year, _currentMonth.month, 1).weekday; // 1=Mon, 7=Sun

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => _changeMonth(-1)),
            Text(DateFormat('yyyy年MM月').format(_currentMonth)),
            IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => _changeMonth(1)),
          ],
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // 星期头
          Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: ["一","二","三","四","五","六","日"].map((e) => Text(e, style: const TextStyle(color: Colors.grey))).toList()),
          const SizedBox(height: 10),
          // 日历网格
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(10),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7, childAspectRatio: 0.7),
              itemCount: daysInMonth + (firstWeekday - 1),
              itemBuilder: (ctx, i) {
                if (i < firstWeekday - 1) return const SizedBox();
                final day = i - (firstWeekday - 1) + 1;
                final inc = _dailyInc[day];
                final exp = _dailyExp[day];

                return Container(
                  margin: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey[200]!),
                      borderRadius: BorderRadius.circular(4),
                      color: Colors.white
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text("$day", style: const TextStyle(fontWeight: FontWeight.bold)),
                      if (inc != null) Text("+${inc.toInt()}", style: const TextStyle(fontSize: 8, color: Colors.green)),
                      if (exp != null) Text("-${exp.toInt()}", style: const TextStyle(fontSize: 8, color: Colors.red)),
                    ],
                  ),
                );
              },
            ),
          ),
          // 底部简单列表
          Container(
            height: 200,
            color: Colors.white,
            child: ListView.builder(
              itemCount: _monthRecords.length,
              itemBuilder: (ctx, i) {
                final r = _monthRecords[i];
                return ListTile(
                  dense: true,
                  title: Text(r['item_name']),
                  trailing: Text("${r['record_type']==1?'+':'-'}${r['amount']}", style: TextStyle(color: r['record_type']==1?Colors.green:Colors.red)),
                  subtitle: Text(r['date']),
                );
              },
            ),
          )
        ],
      ),
    );
  }
}

// ================== 5. 欠款页 ==================

class DebtsPage extends StatefulWidget {
  const DebtsPage({super.key});
  @override
  State<DebtsPage> createState() => _DebtsPageState();
}

class _DebtsPageState extends State<DebtsPage> {
  List<Map<String, dynamic>> _debts = [];
  double _total = 0;

  @override
  void initState() {
    super.initState();
    _loadDebts();
  }

  Future<void> _loadDebts() async {
    final data = await DatabaseHelper.instance.getDebts();
    double t = 0;
    for (var d in data) t += d['amount'];
    setState(() {
      _debts = data;
      _total = t;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("欠款小本本")),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            color: Colors.white,
            child: Column(
              children: [
                const Text("总欠款 (老板欠你的)", style: TextStyle(color: Colors.grey)),
                Text("¥${_total.toStringAsFixed(0)}", style: const TextStyle(fontSize: 32, color: Colors.red, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _debts.length,
              padding: const EdgeInsets.all(16),
              itemBuilder: (ctx, i) {
                final d = _debts[i];
                return Card(
                  color: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(d['boss_name'], style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                            Text("¥${d['amount']}", style: const TextStyle(fontSize: 18, color: Colors.red, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        Text(d['note'] ?? "无备注", style: const TextStyle(color: Colors.grey)),
                        Text(d['date'], style: const TextStyle(fontSize: 12, color: Colors.grey)),
                        const Divider(),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton.icon(
                              icon: const Icon(Icons.check_circle, color: Colors.green),
                              label: const Text("已还款", style: TextStyle(color: Colors.green)),
                              onPressed: () => _repay(d),
                            ),
                            TextButton.icon(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              label: const Text("删除", style: TextStyle(color: Colors.red)),
                              onPressed: () async {
                                await DatabaseHelper.instance.deleteDebt(d['id']);
                                _loadDebts();
                              },
                            ),
                          ],
                        )
                      ],
                    ),
                  ),
                );
              },
            ),
          )
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addDebtDialog,
        backgroundColor: Colors.red,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  void _repay(Map<String, dynamic> debt) async {
    // 1. 转入收入记录
    await DatabaseHelper.instance.addRecord(
        "${debt['boss_name']}还款",
        debt['amount'],
        1, // income
        DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())
    );
    // 2. 删除欠款
    await DatabaseHelper.instance.deleteDebt(debt['id']);
    // 3. 刷新
    _loadDebts();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("已转入收入账本！")));
  }

  void _addDebtDialog() {
    final bossCtrl = TextEditingController();
    final amtCtrl = TextEditingController();
    final noteCtrl = TextEditingController();

    showModalBottomSheet(
        context: context, isScrollControlled: true,
        builder: (ctx) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom + 20, top: 20, left: 20, right: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("记一笔欠款", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              TextField(controller: bossCtrl, decoration: const InputDecoration(labelText: "老板名字"), autofocus: true),
              TextField(controller: amtCtrl, decoration: const InputDecoration(labelText: "欠多少？", prefixText: "¥ "), keyboardType: TextInputType.number),
              TextField(controller: noteCtrl, decoration: const InputDecoration(labelText: "备注")),
              const SizedBox(height: 20),
              SizedBox(width: double.infinity, child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                onPressed: () async {
                  if (amtCtrl.text.isEmpty) return;
                  await DatabaseHelper.instance.addDebt(
                      bossCtrl.text.isEmpty ? "匿名老板" : bossCtrl.text,
                      double.parse(amtCtrl.text),
                      noteCtrl.text,
                      DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())
                  );
                  if (mounted) { Navigator.pop(ctx); _loadDebts(); }
                },
                child: const Text("保存"),
              ))
            ],
          ),
        )
    );
  }
}