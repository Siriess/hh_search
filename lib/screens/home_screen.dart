import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/vacancy.dart';
import '../services/hh_api_service.dart';
import '../services/export_service.dart';
import '../widgets/glass_card.dart';

// Ключи передаются при сборке через --dart-define и хранятся в GitHub Secrets
const _kClientId = String.fromEnvironment('HH_CLIENT_ID');
const _kClientSecret = String.fromEnvironment('HH_CLIENT_SECRET');

const _purple = Color(0xFF8B5CF6);
const _pink = Color(0xFFEC4899);
const _teal = Color(0xFF06B6D4);
const _green = Color(0xFF10B981);

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  final _searchQueryCtrl = TextEditingController(
    text:
        'иностр* OR foreign OR English OR англ* OR зарубеж* OR A1 OR A2 OR B1 OR B2 OR C1 OR международ* OR перевод*',
  );
  final _areaCtrl = TextEditingController();
  final _logScrollCtrl = ScrollController();
  late final TabController _tabCtrl;

  DateTime _dateFrom = DateTime.now().subtract(const Duration(days: 30));
  DateTime _dateTo = DateTime.now();

  SearchState _state = const SearchState();
  HhApiService? _apiService;
  StreamSubscription<SearchState>? _subscription;
  final List<String> _log = [];

  bool get _isRunning =>
      _state.status == SearchStatus.gettingToken ||
      _state.status == SearchStatus.estimating ||
      _state.status == SearchStatus.collectingIds ||
      _state.status == SearchStatus.fetchingDetails;
  bool get _isPaused => _state.status == SearchStatus.paused;
  bool get _hasVacancies => _state.vacancies.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _searchQueryCtrl.dispose();
    _areaCtrl.dispose();
    _logScrollCtrl.dispose();
    _tabCtrl.dispose();
    super.dispose();
  }

  void _addLog(String msg) {
    setState(() {
      _log.add('[${DateFormat('HH:mm:ss').format(DateTime.now())}] $msg');
      if (_log.length > 500) _log.removeAt(0);
    });
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final initial = isFrom ? _dateFrom : _dateTo;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: _purple,
            onPrimary: Colors.white,
            surface: Color(0xFF1A1A3A),
            onSurface: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        if (isFrom) {
          _dateFrom = DateTime(picked.year, picked.month, picked.day, 0, 0, 0);
        } else {
          _dateTo = DateTime(picked.year, picked.month, picked.day, 23, 59, 59);
        }
      });
    }
  }

  void _start() {
    final query = _searchQueryCtrl.text.trim();
    if (query.isEmpty) {
      _showError('Введите поисковый запрос');
      return;
    }
    _log.clear();
    setState(() => _state = const SearchState());
    _apiService =
        HhApiService(clientId: _kClientId, clientSecret: _kClientSecret);

    _subscription = _apiService!
        .searchAll(
          text: query,
          area: _areaCtrl.text.trim().isEmpty ? null : _areaCtrl.text.trim(),
          dateFrom: _dateFrom,
          dateTo: _dateTo,
        )
        .listen(
          (state) {
            setState(() => _state = state);
            if (state.message.isNotEmpty) _addLog(state.message);
            if (state.errorMessage != null) {
              _addLog('ОШИБКА: ${state.errorMessage}');
            }
            // Авто-переключаем на вкладку вакансий когда появились данные
            if (state.vacancies.isNotEmpty && _tabCtrl.index == 0) {
              _tabCtrl.animateTo(1);
            }
          },
          onError: (e) {
            setState(() => _state = SearchState(
                  status: SearchStatus.error,
                  errorMessage: e.toString(),
                  message: 'Ошибка',
                ));
            _addLog('ОШИБКА: $e');
          },
          onDone: () => _addLog('Завершено'),
        );
  }

  void _pause() {
    _apiService?.pause();
    setState(() => _state =
        _state.copyWith(status: SearchStatus.paused, message: 'Пауза'));
    _addLog('Пауза');
  }

  void _resume() {
    _apiService?.resume();
    setState(() => _state = _state.copyWith(
        status: SearchStatus.fetchingDetails, message: 'Возобновление...'));
    _addLog('Возобновление');
  }

  void _cancel() {
    _apiService?.cancel();
    _subscription?.cancel();
    setState(() => _state = SearchState(
          status: SearchStatus.idle,
          message: 'Отменено',
          vacancies: _state.vacancies,
          totalExpected: _state.totalExpected,
          totalDetailsFetched: _state.totalDetailsFetched,
          totalIdsCollected: _state.totalIdsCollected,
        ));
    _addLog('Отменено');
  }

  Future<void> _exportCsv() async {
    if (!_hasVacancies) return;
    try {
      _addLog('Открытие диалога сохранения CSV...');
      final paths = await ExportService.exportToCsv(_state.vacancies);
      if (paths == null) {
        _addLog('Сохранение отменено');
        return;
      }
      for (final p in paths) {
        _addLog('CSV сохранён: $p');
      }
      final msg = paths.length == 1
          ? 'CSV сохранён:\n${paths.first}'
          : 'CSV разбит на ${paths.length} файла:\n${paths.first}\n...';
      _showSuccess(msg);
    } catch (e) {
      _showError('Ошибка CSV: $e');
    }
  }

  Future<void> _exportExcel() async {
    if (!_hasVacancies) return;
    try {
      _addLog('Открытие диалога сохранения Excel...');
      final paths = await ExportService.exportToExcel(_state.vacancies);
      if (paths == null) {
        _addLog('Сохранение отменено');
        return;
      }
      for (final p in paths) {
        _addLog('Excel сохранён: $p');
      }
      final msg = paths.length == 1
          ? 'Excel сохранён:\n${paths.first}'
          : 'Excel разбит на ${paths.length} файла:\n${paths.first}\n...';
      _showSuccess(msg);
    } catch (e) {
      _showError('Ошибка Excel: $e');
    }
  }

  void _showSuccess(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: const Color(0xFF064E3B),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      duration: const Duration(seconds: 6),
    ));
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: const Color(0xFF7F1D1D),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  void _showDescription(VacancyFull v) {
    showDialog(
      context: context,
      builder: (ctx) => _DescriptionDialog(vacancy: v),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080818),
      body: Column(
        children: [
          _buildTopBar(),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSidebar(),
                Expanded(child: _buildMainContent()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── TOP BAR ────────────────────────────────────────────────────────────────
  Widget _buildTopBar() {
    return Container(
      height: 56,
      decoration: const BoxDecoration(
        color: Color(0xFF0D0D22),
        border: Border(bottom: BorderSide(color: Color(0xFF1E1E40))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          ShaderMask(
            shaderCallback: (b) =>
                const LinearGradient(colors: [_purple, _pink]).createShader(b),
            child: const Text(
              'HH Vacancy Export',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: 0.5),
            ),
          ),
          const SizedBox(width: 10),
          _pill('v1.0', _purple),
          const Spacer(),
          _statusDot(),
        ],
      ),
    );
  }

  Widget _statusDot() {
    final (color, label) = switch (_state.status) {
      SearchStatus.idle => (Colors.grey, 'Готов'),
      SearchStatus.gettingToken => (_teal, 'Авторизация'),
      SearchStatus.estimating => (_teal, 'Подсчёт'),
      SearchStatus.collectingIds => (_purple, 'Сбор ID'),
      SearchStatus.fetchingDetails => (const Color(0xFF3B82F6), 'Загрузка'),
      SearchStatus.done => (_green, 'Готово'),
      SearchStatus.error => (_pink, 'Ошибка'),
      SearchStatus.paused => (const Color(0xFFF59E0B), 'Пауза'),
    };
    return Row(children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 6)],
        ),
      ),
      const SizedBox(width: 8),
      Text(label, style: TextStyle(color: color, fontSize: 13)),
    ]);
  }

  // ─── SIDEBAR ────────────────────────────────────────────────────────────────
  Widget _buildSidebar() {
    final fmt = DateFormat('dd.MM.yy');
    return Container(
      width: 310,
      decoration: const BoxDecoration(
        color: Color(0xFF0D0D22),
        border: Border(right: BorderSide(color: Color(0xFF1E1E40))),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _label('ПОИСКОВЫЙ ЗАПРОС'),
          const SizedBox(height: 8),
          TextField(
            controller: _searchQueryCtrl,
            maxLines: 4,
            enabled: !_isRunning,
            style: const TextStyle(fontSize: 12, color: Color(0xFFCCCCEE)),
            decoration: const InputDecoration(hintText: 'иностр* OR English ...'),
          ),
          const SizedBox(height: 14),
          _label('РЕГИОН'),
          const SizedBox(height: 8),
          TextField(
            controller: _areaCtrl,
            enabled: !_isRunning,
            style: const TextStyle(fontSize: 13, color: Color(0xFFCCCCEE)),
            decoration: const InputDecoration(
              hintText: 'пусто = вся Россия  |  2 = СПб  |  1 = МСК',
            ),
          ),
          const SizedBox(height: 14),
          _label('ПЕРИОД ПУБЛИКАЦИИ'),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: _datePicker(
                label: 'С',
                value: fmt.format(_dateFrom),
                onTap: _isRunning ? null : () => _pickDate(isFrom: true),
              ),
            ),
            const SizedBox(width: 8),
            const Text('—', style: TextStyle(color: Color(0xFF555580))),
            const SizedBox(width: 8),
            Expanded(
              child: _datePicker(
                label: 'По',
                value: fmt.format(_dateTo),
                onTap: _isRunning ? null : () => _pickDate(isFrom: false),
              ),
            ),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            Icon(Icons.info_outline,
                size: 12, color: _pink.withValues(alpha: 0.7)),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                'Шире период = дольше загрузка',
                style: TextStyle(
                    fontSize: 11, color: _pink.withValues(alpha: 0.7)),
              ),
            ),
          ]),
          const SizedBox(height: 24),
          _buildActions(),
        ]),
      ),
    );
  }

  Widget _buildActions() {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (!_isRunning && !_isPaused)
        GradientButton(
          onTap: _start,
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text('Начать поиск',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14)),
            ],
          ),
        ),
      if (_isRunning) ...[
        GradientButton(
          onTap: _pause,
          colors: const [Color(0xFFD97706), Color(0xFFEF4444)],
          child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.pause_rounded, color: Colors.white, size: 20),
            SizedBox(width: 8),
            Text('Пауза',
                style:
                    TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          ]),
        ),
        const SizedBox(height: 8),
        _outlineBtn('Отмена', Icons.stop_rounded, _cancel),
      ],
      if (_isPaused) ...[
        GradientButton(
          onTap: _resume,
          child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20),
            SizedBox(width: 8),
            Text('Продолжить',
                style:
                    TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          ]),
        ),
        const SizedBox(height: 8),
        _outlineBtn('Отмена', Icons.stop_rounded, _cancel),
      ],
      if (_hasVacancies) ...[
        const SizedBox(height: 16),
        const Divider(color: Color(0xFF1E1E40)),
        const SizedBox(height: 12),
        _label('ЭКСПОРТ'),
        const SizedBox(height: 10),
        GradientButton(
          onTap: _exportExcel,
          colors: const [Color(0xFF059669), Color(0xFF0D9488)],
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.table_chart_rounded, color: Colors.white, size: 17),
            const SizedBox(width: 8),
            Text(
              'Excel  (${_fmt(_state.vacancies.length)})',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ]),
        ),
        const SizedBox(height: 8),
        GradientButton(
          onTap: _exportCsv,
          colors: const [Color(0xFF0891B2), Color(0xFF6366F1)],
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.download_rounded, color: Colors.white, size: 17),
            const SizedBox(width: 8),
            Text(
              'CSV  (${_fmt(_state.vacancies.length)})',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ]),
        ),
      ],
    ]);
  }

  Widget _outlineBtn(String label, IconData icon, VoidCallback onTap) {
    return SizedBox(
      height: 46,
      child: OutlinedButton.icon(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Color(0xFF2D2D5E)),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          foregroundColor: const Color(0xFF9090C0),
        ),
        icon: Icon(icon, size: 18),
        label: Text(label, style: const TextStyle(fontSize: 13)),
      ),
    );
  }

  // ─── MAIN CONTENT ───────────────────────────────────────────────────────────
  Widget _buildMainContent() {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
        child: _buildStatsRow(),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
        child: _buildProgressCard(),
      ),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: _buildTabPanel(),
        ),
      ),
    ]);
  }

  Widget _buildStatsRow() {
    final s = _state;
    final pct = s.totalIdsCollected > 0
        ? (s.totalDetailsFetched / s.totalIdsCollected * 100)
            .toStringAsFixed(1)
        : '—';

    return Row(children: [
      _statCard(
        label: 'Всего в базе',
        value: s.totalExpected > 0 ? _fmt(s.totalExpected) : '—',
        icon: Icons.search_rounded,
        colors: const [Color(0xFF7C3AED), Color(0xFF6366F1)],
      ),
      const SizedBox(width: 12),
      _statCard(
        label: 'ID собрано',
        value: _fmt(s.totalIdsCollected),
        icon: Icons.tag_rounded,
        colors: const [_purple, Color(0xFF8B5CF6)],
      ),
      const SizedBox(width: 12),
      _statCard(
        label: 'Описаний загружено',
        value: _fmt(s.totalDetailsFetched),
        icon: Icons.description_rounded,
        colors: const [_pink, Color(0xFFF43F5E)],
      ),
      const SizedBox(width: 12),
      _statCard(
        label: 'Выполнено',
        value: '$pct%',
        icon: Icons.donut_large_rounded,
        colors: const [_teal, Color(0xFF0EA5E9)],
      ),
      const SizedBox(width: 12),
      _statCard(
        label: 'Осталось',
        value: _estimateTime(s),
        icon: Icons.schedule_rounded,
        colors: const [Color(0xFFF59E0B), Color(0xFFEF4444)],
      ),
    ]);
  }

  Widget _statCard({
    required String label,
    required String value,
    required IconData icon,
    required List<Color> colors,
  }) {
    return Expanded(
      child: GlassCard(
        padding: const EdgeInsets.all(14),
        glowColor: colors.first,
        child: Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: colors),
              borderRadius: BorderRadius.circular(9),
              boxShadow: [
                BoxShadow(
                    color: colors.first.withValues(alpha: 0.4), blurRadius: 10)
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value,
                    style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Colors.white)),
                Text(label,
                    style: const TextStyle(
                        fontSize: 10, color: Color(0xFF7070A0))),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildProgressCard() {
    final s = _state;

    return GlassCard(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('Прогресс',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              s.message.isEmpty ? 'Ожидание запуска' : s.message,
              style: const TextStyle(fontSize: 11, color: Color(0xFF8888BB)),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ]),
        const SizedBox(height: 14),
        if (s.status == SearchStatus.idle) ...[
          _progressRow('Сбор ID', 0.0, '—', '—'),
          const SizedBox(height: 8),
          _progressRow('Загрузка описаний', 0.0, '—', '—'),
        ] else ...[
          _progressRow(
            'Сбор ID вакансий',
            s.idsProgress,
            _fmt(s.totalIdsCollected),
            s.totalExpected > 0 ? _fmt(s.totalExpected) : '?',
            color1: _purple,
            color2: const Color(0xFF6366F1),
            running: s.status == SearchStatus.collectingIds ||
                s.status == SearchStatus.estimating,
          ),
          const SizedBox(height: 8),
          _progressRow(
            'Загрузка описаний',
            s.detailsProgress,
            _fmt(s.totalDetailsFetched),
            _fmt(s.totalIdsCollected),
            color1: _pink,
            color2: _teal,
            running: s.status == SearchStatus.fetchingDetails,
          ),
        ],
        if (s.errorMessage != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF2D0A0A),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _pink.withValues(alpha: 0.3)),
            ),
            child: Row(children: [
              const Icon(Icons.error_outline, color: _pink, size: 15),
              const SizedBox(width: 8),
              Expanded(
                child: Text(s.errorMessage!,
                    style:
                        const TextStyle(color: Color(0xFFFFAAAA), fontSize: 11)),
              ),
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _progressRow(
    String label,
    double value,
    String current,
    String total, {
    Color color1 = _purple,
    Color color2 = _pink,
    bool running = false,
  }) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(label,
            style: const TextStyle(fontSize: 11, color: Color(0xFF8888AA))),
        const Spacer(),
        Text(
          '$current / $total',
          style: const TextStyle(
              fontSize: 11,
              color: Colors.white,
              fontWeight: FontWeight.w500),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 36,
          child: Text(
            value > 0 ? '${(value * 100).toStringAsFixed(0)}%' : '',
            textAlign: TextAlign.right,
            style: TextStyle(
                fontSize: 11,
                color: color1,
                fontWeight: FontWeight.w600),
          ),
        ),
      ]),
      const SizedBox(height: 5),
      running && value == 0
          ? _indeterminateBar(color1, color2)
          : GradientProgressBar(
              value: value,
              height: 6,
              colors: [color1, color2],
            ),
    ]);
  }

  Widget _indeterminateBar(Color c1, Color c2) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.2, end: 1.0),
      duration: const Duration(milliseconds: 600),
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: GradientProgressBar(value: 1.0, height: 6, colors: [c1, c2]),
      ),
      onEnd: () => setState(() {}),
    );
  }

  // ─── TAB PANEL ───────────────────────────────────────────────────────────────
  Widget _buildTabPanel() {
    return GlassCard(
      padding: EdgeInsets.zero,
      child: Column(children: [
        _buildTabBar(),
        Expanded(
          child: TabBarView(
            controller: _tabCtrl,
            children: [
              _buildLogTab(),
              _buildVacanciesTab(),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _buildTabBar() {
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF1E1E40))),
      ),
      child: TabBar(
        controller: _tabCtrl,
        dividerColor: Colors.transparent,
        indicatorColor: _purple,
        indicatorWeight: 2,
        labelColor: Colors.white,
        unselectedLabelColor: const Color(0xFF555580),
        tabs: [
          Tab(
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: _isRunning ? _green : Colors.grey,
                  shape: BoxShape.circle,
                  boxShadow: _isRunning
                      ? [BoxShadow(color: _green.withValues(alpha: 0.6), blurRadius: 4)]
                      : [],
                ),
              ),
              const SizedBox(width: 8),
              const Text('Лог', style: TextStyle(fontSize: 13)),
            ]),
          ),
          Tab(
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.list_alt_rounded, size: 15),
              const SizedBox(width: 6),
              Text(
                _hasVacancies
                    ? 'Вакансии (${_fmt(_state.vacancies.length)})'
                    : 'Вакансии',
                style: const TextStyle(fontSize: 13),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _buildLogTab() {
    return _log.isEmpty
        ? const Center(
            child: Text('Запустите поиск',
                style: TextStyle(color: Color(0xFF333360), fontSize: 13)),
          )
        : ListView.builder(
            controller: _logScrollCtrl,
            reverse: true,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: _log.length,
            itemBuilder: (_, i) {
              final line = _log[_log.length - 1 - i];
              final isError = line.contains('ОШИБКА');
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 1.5),
                child: RichText(
                  text: TextSpan(
                    style: TextStyle(
                        fontSize: 11,
                        fontFamily: 'Courier New',
                        color:
                            isError ? _pink : const Color(0xFF9090C0)),
                    children: [
                      TextSpan(
                        text: line.length > 10 ? line.substring(0, 10) : line,
                        style: const TextStyle(color: Color(0xFF444470)),
                      ),
                      TextSpan(text: line.length > 10 ? line.substring(10) : ''),
                    ],
                  ),
                ),
              );
            },
          );
  }

  Widget _buildVacanciesTab() {
    final vacancies = _state.vacancies;
    if (vacancies.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.search_off_rounded,
              size: 48, color: Colors.white.withValues(alpha: 0.1)),
          const SizedBox(height: 12),
          const Text('Вакансии появятся здесь в процессе загрузки',
              style: TextStyle(color: Color(0xFF333360), fontSize: 13)),
        ]),
      );
    }

    return Column(children: [
      // Шапка таблицы
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: const BoxDecoration(
          color: Color(0xFF0F0F28),
          border: Border(bottom: BorderSide(color: Color(0xFF1E1E40))),
        ),
        child: Row(children: [
          _colHeader('Название', flex: 4),
          _colHeader('Работодатель', flex: 3),
          _colHeader('Регион', flex: 2),
          _colHeader('Дата', flex: 2),
          const SizedBox(width: 80),
        ]),
      ),
      // Список
      Expanded(
        child: ListView.builder(
          itemCount: vacancies.length,
          itemBuilder: (_, i) => _vacancyRow(vacancies[i], i),
        ),
      ),
    ]);
  }

  Widget _colHeader(String label, {int flex = 1}) {
    return Expanded(
      flex: flex,
      child: Text(label,
          style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFF6060A0),
              letterSpacing: 0.5)),
    );
  }

  Widget _vacancyRow(VacancyFull v, int index) {
    final isEven = index % 2 == 0;
    return InkWell(
      onTap: () => _showDescription(v),
      hoverColor: _purple.withValues(alpha: 0.06),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isEven
              ? Colors.transparent
              : Colors.white.withValues(alpha: 0.015),
          border: const Border(
              bottom: BorderSide(color: Color(0xFF12122A))),
        ),
        child: Row(children: [
          Expanded(
            flex: 4,
            child: Text(
              v.name,
              style: const TextStyle(
                  fontSize: 12,
                  color: Colors.white,
                  fontWeight: FontWeight.w500),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              v.employerName ?? '—',
              style: const TextStyle(fontSize: 11, color: Color(0xFF9090B0)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              v.areaName ?? '—',
              style: const TextStyle(fontSize: 11, color: Color(0xFF9090B0)),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              _shortDate(v.publishedAt),
              style: const TextStyle(fontSize: 11, color: Color(0xFF666690)),
            ),
          ),
          SizedBox(
            width: 80,
            child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              _pill('ред.', _purple.withValues(alpha: 0.8)),
            ]),
          ),
        ]),
      ),
    );
  }

  // ─── HELPERS ─────────────────────────────────────────────────────────────────
  Widget _label(String text) {
    return Text(text,
        style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: Color(0xFF5050A0),
            letterSpacing: 1.0));
  }

  Widget _pill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(text, style: TextStyle(fontSize: 10, color: color)),
    );
  }

  Widget _datePicker(
      {required String label,
      required String value,
      VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C3A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF2D2D5E)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: const TextStyle(fontSize: 10, color: Color(0xFF555580))),
          const SizedBox(height: 2),
          Row(children: [
            Text(value,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Colors.white)),
            const Spacer(),
            const Icon(Icons.calendar_today_rounded,
                size: 12, color: Color(0xFF555580)),
          ]),
        ]),
      ),
    );
  }

  String _fmt(int n) {
    if (n == 0) return '0';
    return NumberFormat('#,##0', 'ru_RU').format(n).replaceAll(',', '\u00A0');
  }

  String _shortDate(String? iso) {
    if (iso == null || iso.isEmpty) return '—';
    try {
      final dt = DateTime.parse(iso);
      return DateFormat('dd.MM.yy').format(dt);
    } catch (_) {
      return iso.substring(0, iso.length.clamp(0, 10));
    }
  }

  String _estimateTime(SearchState s) {
    if (s.totalDetailsFetched == 0 || s.totalIdsCollected == 0) return '—';
    final remaining = s.totalIdsCollected - s.totalDetailsFetched;
    final seconds = (remaining * 0.35).round();
    if (seconds < 60) return '$seconds с';
    if (seconds < 3600) return '${(seconds / 60).round()} м';
    return '${(seconds / 3600).toStringAsFixed(1)} ч';
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Диалог просмотра описания вакансии
// ══════════════════════════════════════════════════════════════════════════════
class _DescriptionDialog extends StatelessWidget {
  final VacancyFull vacancy;
  const _DescriptionDialog({required this.vacancy});

  @override
  Widget build(BuildContext context) {
    final plainText = ExportService.stripHtml(vacancy.description);

    return Dialog(
      backgroundColor: const Color(0xFF12122A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 720,
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Заголовок
          Container(
            padding: const EdgeInsets.fromLTRB(24, 20, 16, 16),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFF1E1E40))),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        vacancy.name,
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.white),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        [
                          if (vacancy.employerName != null)
                            vacancy.employerName!,
                          if (vacancy.areaName != null) vacancy.areaName!,
                        ].join('  •  '),
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF8888AA)),
                      ),
                    ]),
              ),
              const SizedBox(width: 12),
              Row(children: [
                if (vacancy.alternateUrl != null)
                  IconButton(
                    tooltip: 'Скопировать ссылку',
                    icon: const Icon(Icons.link, color: Color(0xFF8888AA)),
                    onPressed: () {
                      Clipboard.setData(
                          ClipboardData(text: vacancy.alternateUrl!));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Ссылка скопирована'),
                          duration: Duration(seconds: 2),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                  ),
                IconButton(
                  icon: const Icon(Icons.close, color: Color(0xFF8888AA)),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ]),
            ]),
          ),
          // Описание
          Expanded(
            child: Scrollbar(
              thumbVisibility: true,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: SelectableText(
                  plainText.isEmpty ? 'Описание недоступно' : plainText,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFFCCCCEE),
                    height: 1.6,
                  ),
                ),
              ),
            ),
          ),
          // Подвал
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Color(0xFF1E1E40))),
            ),
            child: Row(children: [
              Text(
                'ID: ${vacancy.id}',
                style: const TextStyle(
                    fontSize: 11, color: Color(0xFF444470)),
              ),
              const SizedBox(width: 16),
              if (vacancy.publishedAt != null)
                Text(
                  'Опубликовано: ${vacancy.publishedAt!.substring(0, 10)}',
                  style: const TextStyle(
                      fontSize: 11, color: Color(0xFF444470)),
                ),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Закрыть'),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
