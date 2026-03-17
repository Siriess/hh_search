import 'dart:convert';
import 'dart:io';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:html/parser.dart' as html_parser;
import '../models/vacancy.dart';

class ExportService {
  // Excel жёсткий лимит — 1 048 576 строк на лист (1 строка — заголовок).
  // Оставляем запас → по 900 000 строк на лист, чтобы файл не был слишком тяжёлым.
  static const int _excelRowsPerSheet = 900000;

  static String stripHtml(String html) {
    if (html.isEmpty) return '';
    try {
      final document = html_parser.parse(html);
      return document.body?.text.trim() ?? html;
    } catch (_) {
      return html.replaceAll(RegExp(r'<[^>]*>'), '').trim();
    }
  }

  static String _timestamp() {
    return DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-')
        .substring(0, 19);
  }

  static final _headers = [
    'ID',
    'Название вакансии',
    'Описание',
    'Работодатель',
    'Регион',
    'Дата публикации',
    'Ссылка',
  ];

  // ── CSV ────────────────────────────────────────────────────────────────────
  /// Сохраняет CSV. Если вакансий > 1 000 000 — автоматически разбивает
  /// на несколько файлов (_part1, _part2, ...).
  /// Возвращает список сохранённых путей или null если пользователь отменил.
  static Future<List<String>?> exportToCsv(List<VacancyFull> vacancies) async {
    final String? savePath = await FilePicker.platform.saveFile(
      dialogTitle: 'Сохранить CSV',
      fileName: 'hh_vacancies_${_timestamp()}.csv',
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );
    if (savePath == null) return null;

    const csvLimit = 1000000; // CSV ограничен только памятью, но делаем части для удобства
    final needsSplit = vacancies.length > csvLimit;
    final parts = needsSplit
        ? _splitList(vacancies, csvLimit)
        : [vacancies];

    final savedPaths = <String>[];
    final basePath = savePath.endsWith('.csv')
        ? savePath.substring(0, savePath.length - 4)
        : savePath;

    for (int i = 0; i < parts.length; i++) {
      final path = parts.length == 1
          ? '$basePath.csv'
          : '${basePath}_part${i + 1}.csv';

      final rows = <List<dynamic>>[_headers];
      for (final v in parts[i]) {
        rows.add(_rowValues(v));
      }

      final csvData = const ListToCsvConverter(
        fieldDelimiter: ';',
        textDelimiter: '"',
        eol: '\r\n',
      ).convert(rows);

      await File(path).writeAsString('\uFEFF$csvData', encoding: utf8);
      savedPaths.add(path);
    }

    return savedPaths;
  }

  // ── Excel ──────────────────────────────────────────────────────────────────
  /// Сохраняет Excel. Если вакансий > 900 000 — создаёт несколько листов
  /// (Вакансии 1, Вакансии 2, ...) в одном файле.
  /// Возвращает список сохранённых путей или null если пользователь отменил.
  static Future<List<String>?> exportToExcel(List<VacancyFull> vacancies) async {
    final String? savePath = await FilePicker.platform.saveFile(
      dialogTitle: 'Сохранить Excel',
      fileName: 'hh_vacancies_${_timestamp()}.xlsx',
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
    );
    if (savePath == null) return null;

    final path = savePath.endsWith('.xlsx') ? savePath : '$savePath.xlsx';

    // Сколько листов нужно
    final parts = _splitList(vacancies, _excelRowsPerSheet);
    final sheetsCount = parts.length;

    final excel = Excel.createExcel();

    for (int p = 0; p < sheetsCount; p++) {
      final sheetName = sheetsCount == 1 ? 'Вакансии' : 'Вакансии ${p + 1}';

      if (p == 0) {
        excel.rename('Sheet1', sheetName);
      } else {
        excel.copy('Вакансии 1', sheetName);
        // очищаем скопированный лист
        final s = excel[sheetName];
        s.removeRow(0);
      }

      final sheet = excel[sheetName];
      sheet.appendRow(_headers.map((h) => TextCellValue(h)).toList());

      final headerStyle = CellStyle(
        bold: true,
        backgroundColorHex: ExcelColor.fromHexString('#7C3AED'),
        fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
      );
      for (int c = 0; c < _headers.length; c++) {
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0))
            .cellStyle = headerStyle;
      }

      sheet.setColumnWidth(0, 15);
      sheet.setColumnWidth(1, 45);
      sheet.setColumnWidth(2, 80);
      sheet.setColumnWidth(3, 30);
      sheet.setColumnWidth(4, 20);
      sheet.setColumnWidth(5, 25);
      sheet.setColumnWidth(6, 40);

      for (final v in parts[p]) {
        sheet.appendRow(_rowValues(v).map((e) => TextCellValue(e)).toList());
      }
    }

    final bytes = excel.save();
    if (bytes == null) throw Exception('Не удалось создать Excel-файл');
    await File(path).writeAsBytes(bytes);

    return [path];
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  static List<String> _rowValues(VacancyFull v) => [
        v.id,
        v.name,
        stripHtml(v.description),
        v.employerName ?? '',
        v.areaName ?? '',
        v.publishedAt ?? '',
        v.alternateUrl ?? '',
      ];

  static List<List<T>> _splitList<T>(List<T> list, int chunkSize) {
    final result = <List<T>>[];
    for (int i = 0; i < list.length; i += chunkSize) {
      result.add(list.sublist(i, (i + chunkSize).clamp(0, list.length)));
    }
    return result;
  }
}
