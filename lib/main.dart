import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;  // 加上 "as p"
// import 'package:path/path.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';

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

  Future<Map<String, double>> getTotalSummary() async {
    final db = await instance.database;
    final incRes = await db.rawQuery("SELECT SUM(amount) as t FROM records WHERE record_type = 1");
    final expRes = await db.rawQuery("SELECT SUM(amount) as t FROM records WHERE record_type = 0");

    double inc = (incRes.first['t'] as num?)?.toDouble() ?? 0.0;
    double exp = (expRes.first['t'] as num?)?.toDouble() ?? 0.0;
    return {'income': inc, 'expense': exp};
  }

  Future<Map<String, double>> getYearSummary(String yearStr) async {
    final db = await instance.database;
    final incRes = await db.rawQuery("SELECT SUM(amount) as t FROM records WHERE record_type = 1 AND date LIKE '$yearStr%'");
    final expRes = await db.rawQuery("SELECT SUM(amount) as t FROM records WHERE record_type = 0 AND date LIKE '$yearStr%'");

    double inc = (incRes.first['t'] as num?)?.toDouble() ?? 0.0;
    double exp = (expRes.first['t'] as num?)?.toDouble() ?? 0.0;
    return {'income': inc, 'expense': exp};
  }

  Future<Map<String, double>> getDaySummary(String dayStr) async {
    final db = await instance.database;
    final incRes = await db.rawQuery("SELECT SUM(amount) as t FROM records WHERE record_type = 1 AND date LIKE '$dayStr%'");
    final expRes = await db.rawQuery("SELECT SUM(amount) as t FROM records WHERE record_type = 0 AND date LIKE '$dayStr%'");

    double inc = (incRes.first['t'] as num?)?.toDouble() ?? 0.0;
    double exp = (expRes.first['t'] as num?)?.toDouble() ?? 0.0;
    return {'income': inc, 'expense': exp};
  }

  // --- 导出导入数据 ---
  Future<String> exportData() async {
    final db = await instance.database;
    final records = await db.query('records');
    final debts = await db.query('debts');

    final data = {
      'records': records,
      'debts': debts,
      'exportDate': DateTime.now().toIso8601String(),
      'version': '15.1',
    };

    return jsonEncode(data);
  }

  Future<bool> importData(String jsonData) async {
    try {
      final data = jsonDecode(jsonData) as Map<String, dynamic>;
      final db = await instance.database;

      // 清空现有数据
      await db.delete('records');
      await db.delete('debts');

      // 导入记录
      if (data['records'] != null) {
        for (var record in data['records']) {
          await db.insert('records', {
            'item_name': record['item_name'],
            'amount': record['amount'],
            'record_type': record['record_type'],
            'date': record['date'],
          });
        }
      }

      // 导入欠款
      if (data['debts'] != null) {
        for (var debt in data['debts']) {
          await db.insert('debts', {
            'boss_name': debt['boss_name'],
            'amount': debt['amount'],
            'note': debt['note'],
            'date': debt['date'],
          });
        }
      }

      return true;
    } catch (e) {
      print('导入失败: $e');
      return false;
    }
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
  final GlobalKey<_HomePageState> _homeKey = GlobalKey<_HomePageState>();
  final GlobalKey<_StatsPageState> _statsKey = GlobalKey<_StatsPageState>();
  final GlobalKey<_DebtsPageState> _debtsKey = GlobalKey<_DebtsPageState>();

  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _pages = [
      HomePage(key: _homeKey),
      StatsPage(key: _statsKey),
      DebtsPage(key: _debtsKey),
    ];
  }

  void _refreshAllPages() {
    _homeKey.currentState?._loadData();
    _statsKey.currentState?._loadMonthData();
    _debtsKey.currentState?._loadDebts();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: _pages), // 保持页面状态
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (idx) {
          setState(() => _selectedIndex = idx);
          // 切换页面时刷新当前页面
          if (idx == 0) _homeKey.currentState?._loadData();
          if (idx == 1) _statsKey.currentState?._loadMonthData();
          if (idx == 2) _debtsKey.currentState?._loadDebts();
        },
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
  String _timeRange = 'all'; // all, year, month, day

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  // 这里的 setState 用于刷新界面
  Future<void> _loadData() async {
    final now = DateTime.now();
    final yearStr = DateFormat('yyyy').format(now);
    final monthStr = DateFormat('yyyy-MM').format(now);
    final dayStr = DateFormat('yyyy-MM-dd').format(now);

    final allRecords = await DatabaseHelper.instance.getRecords(); // 获取所有记录
    Map<String, double> summary;

    switch (_timeRange) {
      case 'year':
        summary = await DatabaseHelper.instance.getYearSummary(yearStr);
        break;
      case 'month':
        summary = await DatabaseHelper.instance.getMonthSummary(monthStr);
        break;
      case 'day':
        summary = await DatabaseHelper.instance.getDaySummary(dayStr);
        break;
      default:
        summary = await DatabaseHelper.instance.getTotalSummary();
    }

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

  String get _timeRangeLabel {
    switch (_timeRange) {
      case 'year': return '本年';
      case 'month': return '本月';
      case 'day': return '本日';
      default: return '全部';
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final dateStr = "${now.year}年${now.month}月${now.day}日";

    return Scaffold(
      appBar: AppBar(
        title: Text("$dateStr 老爸记账"),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              if (value == 'export') {
                _exportData();
              } else if (value == 'import') {
                _importData();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'export', child: Row(children: [Icon(Icons.upload), SizedBox(width: 8), Text('导出数据')])),
              const PopupMenuItem(value: 'import', child: Row(children: [Icon(Icons.download), SizedBox(width: 8), Text('导入数据')])),
            ],
          ),
        ],
      ),
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
                  Text("$_timeRangeLabel结余", style: const TextStyle(color: Colors.grey)),
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
          // 时间范围筛选按钮
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _timeRangeBtn("全部", 'all'),
              const SizedBox(width: 8),
              _timeRangeBtn("本年", 'year'),
              const SizedBox(width: 8),
              _timeRangeBtn("本月", 'month'),
              const SizedBox(width: 8),
              _timeRangeBtn("本日", 'day'),
            ],
          ),
          const SizedBox(height: 10),
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

  Widget _timeRangeBtn(String label, String key) {
    final isSel = _timeRange == key;
    return ChoiceChip(
      label: Text(label, style: TextStyle(color: isSel ? Colors.white : Colors.black, fontSize: 12)),
      selected: isSel,
      selectedColor: Colors.purple,
      onSelected: (v) {
        setState(() => _timeRange = key);
        _loadData();
      },
    );
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

  Future<void> _exportData() async {
    try {
      final jsonData = await DatabaseHelper.instance.exportData();
      final directory = await getApplicationDocumentsDirectory();
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final file = File('${directory.path}/laoba_jizhang_$timestamp.json');
      await file.writeAsString(jsonData);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('数据已导出到: ${file.path}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出失败: $e')),
        );
      }
    }
  }

  Future<void> _importData() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        final jsonData = await file.readAsString();
        final success = await DatabaseHelper.instance.importData(jsonData);

        if (success) {
          _loadData();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('数据导入成功！')),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('数据导入失败，请检查文件格式')),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导入失败: $e')),
        );
      }
    }
  }

  void _showAddDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    final amtCtrl = TextEditingController();
    int type = 0; // 0 exp, 1 inc
    DateTime selectedDateTime = DateTime.now();

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
                const SizedBox(height: 10),
                // 时间选择器
                InkWell(
                  onTap: () async {
                    final date = await showDatePicker(
                      context: ctx,
                      initialDate: selectedDateTime,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (date != null) {
                      final time = await showTimePicker(
                        context: ctx,
                        initialTime: TimeOfDay.fromDateTime(selectedDateTime),
                      );
                      if (time != null) {
                        setModalState(() {
                          selectedDateTime = DateTime(
                            date.year,
                            date.month,
                            date.day,
                            time.hour,
                            time.minute,
                          );
                        });
                      }
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey[300]!),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("选择时间", style: TextStyle(color: Colors.grey)),
                        Text(
                          DateFormat('yyyy-MM-dd HH:mm').format(selectedDateTime),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(width: double.infinity, child: ElevatedButton(
                  onPressed: () async {
                    if (nameCtrl.text.isEmpty || amtCtrl.text.isEmpty) return;
                    await DatabaseHelper.instance.addRecord(
                      nameCtrl.text,
                      double.parse(amtCtrl.text),
                      type,
                      DateFormat('yyyy-MM-dd HH:mm').format(selectedDateTime)
                    );
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
  Set<int> _debtDays = {}; // 有欠款的日期
  String _viewMode = 'month'; // month or year
  Map<int, Map<String, double>> _yearlyData = {}; // 年视图数据

  @override
  void initState() {
    super.initState();
    _loadMonthData();
  }

  Future<void> _loadMonthData() async {
    if (_viewMode == 'year') {
      await _loadYearData();
      return;
    }

    final monthStr = DateFormat('yyyy-MM').format(_currentMonth);
    final data = await DatabaseHelper.instance.getRecords(monthFilter: monthStr);
    final debts = await DatabaseHelper.instance.getDebts();

    Map<int, double> dInc = {};
    Map<int, double> dExp = {};
    Set<int> debtDays = {};

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

    // 标记欠款日期
    for (var debt in debts) {
      final debtDate = debt['date'].toString().split(' ')[0];
      final debtMonthStr = debtDate.substring(0, 7);
      if (debtMonthStr == monthStr) {
        final day = int.parse(debtDate.split('-')[2]);
        debtDays.add(day);
      }
    }

    setState(() {
      _monthRecords = data;
      _dailyInc = dInc;
      _dailyExp = dExp;
      _debtDays = debtDays;
    });
  }

  Future<void> _loadYearData() async {
    final year = _currentMonth.year;
    Map<int, Map<String, double>> yearData = {};

    for (int month = 1; month <= 12; month++) {
      final monthStr = '$year-${month.toString().padLeft(2, '0')}';
      final summary = await DatabaseHelper.instance.getMonthSummary(monthStr);
      yearData[month] = summary;
    }

    setState(() {
      _yearlyData = yearData;
    });
  }

  void _changeMonth(int delta) {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + delta, 1);
    });
    _loadMonthData();
  }

  void _changeYear(int delta) {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year + delta, _currentMonth.month, 1);
    });
    _loadYearData();
  }

  void _toggleViewMode() {
    setState(() {
      _viewMode = _viewMode == 'month' ? 'year' : 'month';
    });
    _loadMonthData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_viewMode == 'month') ...[
              IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => _changeMonth(-1)),
              Text(DateFormat('yyyy年MM月').format(_currentMonth)),
              IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => _changeMonth(1)),
            ] else ...[
              IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => _changeYear(-1)),
              Text('${_currentMonth.year}年'),
              IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => _changeYear(1)),
            ],
          ],
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(_viewMode == 'month' ? Icons.calendar_view_month : Icons.calendar_today),
            onPressed: _toggleViewMode,
            tooltip: _viewMode == 'month' ? '切换到年视图' : '切换到月视图',
          ),
        ],
      ),
      body: _viewMode == 'month' ? _buildMonthView() : _buildYearView(),
    );
  }

  Widget _buildMonthView() {
    final daysInMonth = DateUtils.getDaysInMonth(_currentMonth.year, _currentMonth.month);
    final firstWeekday = DateTime(_currentMonth.year, _currentMonth.month, 1).weekday;

    // 计算本月统计
    double monthInc = 0;
    double monthExp = 0;
    _dailyInc.values.forEach((v) => monthInc += v);
    _dailyExp.values.forEach((v) => monthExp += v);

    return Column(
      children: [
        // 月度统计卡片
        Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8)],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _statItem("收入", monthInc, Colors.green),
              Container(width: 1, height: 40, color: Colors.grey[300]),
              _statItem("支出", monthExp, Colors.red),
              Container(width: 1, height: 40, color: Colors.grey[300]),
              _statItem("结余", monthInc - monthExp, Colors.blue),
            ],
          ),
        ),
        // 星期头
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: ["一","二","三","四","五","六","日"].map((e) => Text(e, style: const TextStyle(color: Colors.grey))).toList(),
        ),
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
              final hasDebt = _debtDays.contains(day);

              return Container(
                margin: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: hasDebt ? Colors.orange : Colors.grey[200]!,
                    width: hasDebt ? 2 : 1,
                  ),
                  borderRadius: BorderRadius.circular(4),
                  color: hasDebt ? Colors.orange[50] : Colors.white,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      "$day",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: hasDebt ? Colors.orange[800] : Colors.black,
                      ),
                    ),
                    if (inc != null) Text("+${inc.toInt()}", style: const TextStyle(fontSize: 8, color: Colors.green)),
                    if (exp != null) Text("-${exp.toInt()}", style: const TextStyle(fontSize: 8, color: Colors.red)),
                    if (hasDebt) const Icon(Icons.account_balance_wallet, size: 10, color: Colors.orange),
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
          child: _monthRecords.isEmpty
              ? const Center(child: Text("本月暂无记录", style: TextStyle(color: Colors.grey)))
              : ListView.builder(
            itemCount: _monthRecords.length,
            itemBuilder: (ctx, i) {
              final r = _monthRecords[i];
              return ListTile(
                dense: true,
                title: Text(r['item_name']),
                trailing: Text(
                  "${r['record_type']==1?'+':'-'}${r['amount']}",
                  style: TextStyle(color: r['record_type']==1?Colors.green:Colors.red),
                ),
                subtitle: Text(r['date']),
              );
            },
          ),
        )
      ],
    );
  }

  Widget _buildYearView() {
    return Column(
      children: [
        // 年度总统计
        Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8)],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _statItem("年收入", _yearlyData.values.fold(0.0, (sum, m) => sum + (m['income'] ?? 0)), Colors.green),
              Container(width: 1, height: 40, color: Colors.grey[300]),
              _statItem("年支出", _yearlyData.values.fold(0.0, (sum, m) => sum + (m['expense'] ?? 0)), Colors.red),
              Container(width: 1, height: 40, color: Colors.grey[300]),
              _statItem("年结余", _yearlyData.values.fold(0.0, (sum, m) => sum + ((m['income'] ?? 0) - (m['expense'] ?? 0))), Colors.blue),
            ],
          ),
        ),
        // 12个月的网格
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 1.0,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: 12,
            itemBuilder: (ctx, i) {
              final month = i + 1;
              final data = _yearlyData[month] ?? {'income': 0.0, 'expense': 0.0};
              final inc = data['income']!;
              final exp = data['expense']!;
              final balance = inc - exp;

              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '$month月',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text('+${inc.toInt()}', style: const TextStyle(fontSize: 12, color: Colors.green)),
                    Text('-${exp.toInt()}', style: const TextStyle(fontSize: 12, color: Colors.red)),
                    const Divider(height: 8),
                    Text(
                      '¥${balance.toInt()}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: balance >= 0 ? Colors.blue : Colors.red,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _statItem(String label, double value, Color color) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 4),
        Text(
          '¥${value.toInt()}',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color),
        ),
      ],
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