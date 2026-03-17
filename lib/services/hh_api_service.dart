import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import '../models/vacancy.dart';

class HhApiException implements Exception {
  final String message;
  final int? statusCode;
  HhApiException(this.message, {this.statusCode});

  @override
  String toString() => 'HhApiException: $message (HTTP $statusCode)';
}

/// Семафор для ограничения числа одновременных запросов.
class _Semaphore {
  _Semaphore(this._max);
  final int _max;
  int _active = 0;
  final _queue = <Completer<void>>[];

  Future<void> acquire() async {
    if (_active < _max) { _active++; return; }
    final c = Completer<void>();
    _queue.add(c);
    await c.future;
    _active++;
  }

  void release() {
    _active--;
    if (_queue.isNotEmpty) _queue.removeAt(0).complete();
  }
}

class HhApiService {
  static const String _baseUrl = 'https://api.hh.ru';
  static const String _tokenUrl = 'https://hh.ru/oauth/token';
  static const int _perPage = 100;
  static const int _maxPage = 19;
  // Задержка только для поиска (сбор ID) — 1 поток, не перегружаем
  static const Duration _searchDelay = Duration(milliseconds: 300);

  // Токен кешируется статически — один на всё приложение, не сбрасывается между запусками
  static String? _cachedToken;
  static DateTime? _tokenObtainedAt;

  final String clientId;
  final String clientSecret;

  bool _cancelled = false;
  bool _paused = false;

  HhApiService({required this.clientId, required this.clientSecret});

  void cancel() => _cancelled = true;
  void pause() => _paused = true;
  void resume() => _paused = false;
  void reset() {
    _cancelled = false;
    _paused = false;
  }

  String get _userAgent => 'HhVacancyExport/1.0 ($clientId@hh.ru)';

  String? get _accessToken => _cachedToken;

  Map<String, String> get _headers {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'User-Agent': _userAgent,
      'HH-User-Agent': _userAgent,
    };
    if (_accessToken != null) {
      headers['Authorization'] = 'Bearer $_accessToken';
    }
    return headers;
  }

  Future<void> authenticate() async {
    // Если токен получен менее 23 часов назад — используем его повторно
    if (_cachedToken != null && _tokenObtainedAt != null) {
      final age = DateTime.now().difference(_tokenObtainedAt!);
      if (age.inHours < 23) {
        return; // токен ещё свежий
      }
    }

    await _requestNewToken();
  }

  Future<void> _requestNewToken({int attempt = 1}) async {
    final response = await http.post(
      Uri.parse(_tokenUrl),
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'User-Agent': _userAgent,
        'HH-User-Agent': _userAgent,
      },
      body: {
        'grant_type': 'client_credentials',
        'client_id': clientId,
        'client_secret': clientSecret,
      },
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final token = data['access_token']?.toString();
      if (token == null) {
        throw HhApiException('Token not found in response');
      }
      _cachedToken = token;
      _tokenObtainedAt = DateTime.now();
    } else if (response.statusCode == 403 &&
        response.body.contains('too early') &&
        attempt <= 3) {
      // HH.ru: слишком ранний повторный запрос — ждём и повторяем
      final waitSec = attempt * 10;
      await Future.delayed(Duration(seconds: waitSec));
      await _requestNewToken(attempt: attempt + 1);
    } else {
      throw HhApiException(
        'Auth failed: ${response.body}',
        statusCode: response.statusCode,
      );
    }
  }

  Future<Map<String, dynamic>> _getVacancies({
    required String text,
    required int page,
    String? dateFrom,
    String? dateTo,
    String? area,
    int perPage = _perPage,
  }) async {
    final params = <String, String>{
      'text': text,
      'per_page': perPage.toString(),
      'page': page.toString(),
      'search_field': 'description',
    };
    if (dateFrom != null) params['date_from'] = dateFrom;
    if (dateTo != null) params['date_to'] = dateTo;
    if (area != null && area.isNotEmpty) params['area'] = area;

    final uri =
        Uri.parse('$_baseUrl/vacancies').replace(queryParameters: params);
    final response = await http.get(uri, headers: _headers);

    if (response.statusCode == 200) {
      return jsonDecode(utf8.decode(response.bodyBytes))
          as Map<String, dynamic>;
    } else if (response.statusCode == 429) {
      await Future.delayed(const Duration(seconds: 5));
      return _getVacancies(
        text: text,
        page: page,
        dateFrom: dateFrom,
        dateTo: dateTo,
        area: area,
        perPage: perPage,
      );
    } else {
      throw HhApiException(
        'Search failed: ${response.body}',
        statusCode: response.statusCode,
      );
    }
  }

  /// Рекурсивно собирает ID вакансий, дробя диапазон дат при превышении 2000.
  Future<void> _collectIdsForRange({
    required String text,
    required DateTime dateFrom,
    required DateTime dateTo,
    required String? area,
    required Set<String> collectedIds,
    required StreamController<SearchState> ctrl,
    required int totalExpected,
  }) async {
    if (_cancelled) return;

    while (_paused) {
      await Future.delayed(const Duration(seconds: 1));
      if (_cancelled) return;
    }

    final fromStr = _formatDate(dateFrom);
    final toStr = _formatDate(dateTo);

    final firstPage = await _getVacancies(
      text: text,
      page: 0,
      dateFrom: fromStr,
      dateTo: toStr,
      area: area,
    );
    await Future.delayed(_searchDelay);

    final found = (firstPage['found'] as num?)?.toInt() ?? 0;
    final maxFetchable = (_maxPage + 1) * _perPage; // 2000

    if (found == 0) return;

    // Если найдено > 2000 — дробим диапазон пополам
    if (found > maxFetchable) {
      final duration = dateTo.difference(dateFrom);
      if (duration.inMinutes <= 1) {
        // Минимальный диапазон — берём что можем
        ctrl.add(SearchState(
          status: SearchStatus.collectingIds,
          totalExpected: totalExpected,
          totalIdsCollected: collectedIds.length,
          message: 'Мин. диапазон $fromStr: берём $maxFetchable из $found',
        ));
      } else {
        final mid = dateFrom.add(Duration(minutes: duration.inMinutes ~/ 2));
        await _collectIdsForRange(
          text: text,
          dateFrom: dateFrom,
          dateTo: mid,
          area: area,
          collectedIds: collectedIds,
          ctrl: ctrl,
          totalExpected: totalExpected,
        );
        if (_cancelled) return;
        await _collectIdsForRange(
          text: text,
          dateFrom: mid,
          dateTo: dateTo,
          area: area,
          collectedIds: collectedIds,
          ctrl: ctrl,
          totalExpected: totalExpected,
        );
        return;
      }
    }

    // Добавляем ID с первой страницы
    final firstItems = firstPage['items'] as List<dynamic>? ?? [];
    for (final item in firstItems) {
      collectedIds
          .add((item as Map<String, dynamic>)['id']?.toString() ?? '');
    }

    final totalPages = (found / _perPage).ceil().clamp(1, _maxPage + 1);
    ctrl.add(SearchState(
      status: SearchStatus.collectingIds,
      totalExpected: totalExpected,
      totalIdsCollected: collectedIds.length,
      message: '$fromStr → $toStr  |  найдено $found, страниц $totalPages',
    ));

    for (int page = 1; page < totalPages; page++) {
      if (_cancelled) return;
      while (_paused) {
        await Future.delayed(const Duration(seconds: 1));
        if (_cancelled) return;
      }

      try {
        final pageData = await _getVacancies(
          text: text,
          page: page,
          dateFrom: fromStr,
          dateTo: toStr,
          area: area,
        );
        final items = pageData['items'] as List<dynamic>? ?? [];
        for (final item in items) {
          collectedIds.add(
              (item as Map<String, dynamic>)['id']?.toString() ?? '');
        }
        await Future.delayed(_searchDelay);
        ctrl.add(SearchState(
          status: SearchStatus.collectingIds,
          totalExpected: totalExpected,
          totalIdsCollected: collectedIds.length,
          message: 'Стр. $page/$totalPages  |  $fromStr',
        ));
      } catch (e) {
        ctrl.add(SearchState(
          status: SearchStatus.collectingIds,
          totalExpected: totalExpected,
          totalIdsCollected: collectedIds.length,
          message: 'Пропуск стр.$page: $e',
        ));
      }
    }
  }

  Future<VacancyFull?> fetchVacancyDetail(String id, {int attempt = 1}) async {
    final uri = Uri.parse('$_baseUrl/vacancies/$id');
    try {
      final response = await http.get(uri, headers: _headers);
      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes))
            as Map<String, dynamic>;
        return VacancyFull.fromJson(data);
      } else if (response.statusCode == 429) {
        if (attempt > 5) return null;
        // Экспоненциальный откат + случайный джиттер чтобы параллельные
        // запросы не навалились одновременно
        final waitMs = (2000 * attempt) + Random().nextInt(1000);
        await Future.delayed(Duration(milliseconds: waitMs));
        return fetchVacancyDetail(id, attempt: attempt + 1);
      } else {
        return null;
      }
    } catch (_) {
      return null;
    }
  }

  Stream<SearchState> searchAll({
    required String text,
    String? area,
    required DateTime dateFrom,
    required DateTime dateTo,
    int concurrency = 8,
  }) {
    final ctrl = StreamController<SearchState>();

    () async {
      reset();
      final collectedIds = <String>{};
      final vacancies = <VacancyFull>[];

      // ── Шаг 1: Авторизация ────────────────────────────────────────────────
      ctrl.add(const SearchState(
        status: SearchStatus.gettingToken,
        message: 'Получение токена...',
      ));
      try {
        await authenticate();
        ctrl.add(const SearchState(
          status: SearchStatus.gettingToken,
          message: 'Токен получен',
        ));
      } catch (e) {
        ctrl.add(SearchState(
          status: SearchStatus.error,
          errorMessage: 'Ошибка авторизации: $e',
          message: 'Ошибка авторизации',
        ));
        await ctrl.close();
        return;
      }

      // ── Шаг 2: Получаем общее кол-во вакансий за выбранный период ─────────
      ctrl.add(const SearchState(
        status: SearchStatus.estimating,
        message: 'Подсчёт общего количества вакансий...',
      ));
      int totalExpected = 0;
      try {
        final countData = await _getVacancies(
          text: text,
          page: 0,
          dateFrom: _formatDate(dateFrom),
          dateTo: _formatDate(dateTo),
          area: area,
          perPage: 1,
        );
        totalExpected = (countData['found'] as num?)?.toInt() ?? 0;
        ctrl.add(SearchState(
          status: SearchStatus.estimating,
          totalExpected: totalExpected,
          message: 'Всего в базе: $totalExpected вакансий',
        ));
        await Future.delayed(_searchDelay);
      } catch (e) {
        ctrl.add(SearchState(
          status: SearchStatus.error,
          errorMessage: 'Ошибка подсчёта: $e',
          message: 'Не удалось получить количество',
        ));
        await ctrl.close();
        return;
      }

      // ── Шаг 3: Сбор ID вакансий по датам ─────────────────────────────────
      ctrl.add(SearchState(
        status: SearchStatus.collectingIds,
        totalExpected: totalExpected,
        message: 'Сбор ID вакансий...',
      ));
      try {
        await _collectIdsForRange(
          text: text,
          dateFrom: dateFrom,
          dateTo: dateTo,
          area: area,
          collectedIds: collectedIds,
          ctrl: ctrl,
          totalExpected: totalExpected,
        );
      } catch (e) {
        ctrl.add(SearchState(
          status: SearchStatus.error,
          errorMessage: 'Ошибка сбора ID: $e',
          message: 'Ошибка при сборе вакансий',
          totalExpected: totalExpected,
          totalIdsCollected: collectedIds.length,
        ));
        await ctrl.close();
        return;
      }

      if (_cancelled) {
        ctrl.add(SearchState(
          status: SearchStatus.paused,
          message: 'Отменено',
          totalExpected: totalExpected,
          totalIdsCollected: collectedIds.length,
          vacancies: List.from(vacancies),
        ));
        await ctrl.close();
        return;
      }

      final ids = collectedIds.where((id) => id.isNotEmpty).toList();
      ctrl.add(SearchState(
        status: SearchStatus.fetchingDetails,
        totalExpected: totalExpected,
        totalIdsCollected: ids.length,
        totalDetailsFetched: 0,
        message: 'Найдено ${ids.length} ID. Загрузка описаний...',
        vacancies: const [],
      ));

      // ── Шаг 4: Параллельная загрузка описаний ────────────────────────────
      final sem = _Semaphore(concurrency);
      int done = 0;

      final futures = ids.map((id) async {
        await sem.acquire();
        try {
          // Пауза/отмена внутри потока
          while (_paused) {
            sem.release();
            await Future.delayed(const Duration(seconds: 1));
            await sem.acquire();
          }
          if (_cancelled) return;

          final vacancy = await fetchVacancyDetail(id);
          if (vacancy != null) vacancies.add(vacancy);
        } finally {
          sem.release();
          done++;
          // Обновляем UI каждые concurrency запросов или в конце
          if (done % concurrency == 0 || done == ids.length) {
            ctrl.add(SearchState(
              status: SearchStatus.fetchingDetails,
              totalExpected: totalExpected,
              totalIdsCollected: ids.length,
              totalDetailsFetched: done,
              message:
                  'Загружено $done из ${ids.length}  •  $concurrency потоков',
              vacancies: List.from(vacancies),
            ));
          }
        }
      }).toList();

      await Future.wait(futures);

      ctrl.add(SearchState(
        status: SearchStatus.done,
        totalExpected: totalExpected,
        totalIdsCollected: ids.length,
        totalDetailsFetched: vacancies.length,
        message: 'Готово! Загружено ${vacancies.length} вакансий.',
        vacancies: List.from(vacancies),
      ));
      await ctrl.close();
    }();

    return ctrl.stream;
  }

  String _formatDate(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final mi = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$y-$m-${d}T$h:$mi:$s+0300';
  }
}
