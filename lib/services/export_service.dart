import 'dart:convert';
import 'dart:io';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:html/parser.dart' as html_parser;
import '../models/vacancy.dart';

class ExportService {
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

  /// Показывает нативный диалог сохранения и сохраняет CSV.
  /// Возвращает путь к файлу или null если пользователь отменил.
  static Future<String?> exportToCsv(List<VacancyFull> vacancies) async {
    final String? savePath = await FilePicker.platform.saveFile(
      dialogTitle: 'Сохранить CSV',
      fileName: 'hh_vacancies_${_timestamp()}.csv',
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );

    if (savePath == null) return null;

    final rows = <List<dynamic>>[
      [
        'ID',
        'Название вакансии',
        'Описание',
        'Работодатель',
        'Регион',
        'Дата публикации',
        'Ссылка',
      ],
    ];

    for (final v in vacancies) {
      rows.add([
        v.id,
        v.name,
        stripHtml(v.description),
        v.employerName ?? '',
        v.areaName ?? '',
        v.publishedAt ?? '',
        v.alternateUrl ?? '',
      ]);
    }

    final csvData = const ListToCsvConverter(
      fieldDelimiter: ';',
      textDelimiter: '"',
      eol: '\r\n',
    ).convert(rows);

    final path = savePath.endsWith('.csv') ? savePath : '$savePath.csv';
    await File(path).writeAsString('\uFEFF$csvData', encoding: utf8);
    return path;
  }

  /// Показывает нативный диалог сохранения и сохраняет Excel.
  /// Возвращает путь к файлу или null если пользователь отменил.
  static Future<String?> exportToExcel(List<VacancyFull> vacancies) async {
    final String? savePath = await FilePicker.platform.saveFile(
      dialogTitle: 'Сохранить Excel',
      fileName: 'hh_vacancies_${_timestamp()}.xlsx',
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
    );

    if (savePath == null) return null;

    final excel = Excel.createExcel();
    excel.rename('Sheet1', 'Вакансии');
    final sheet = excel['Вакансии'];

    final headers = [
      'ID',
      'Название вакансии',
      'Описание',
      'Работодатель',
      'Регион',
      'Дата публикации',
      'Ссылка',
    ];
    sheet.appendRow(headers.map((h) => TextCellValue(h)).toList());

    final headerStyle = CellStyle(
      bold: true,
      backgroundColorHex: ExcelColor.fromHexString('#7C3AED'),
      fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
    );
    for (int c = 0; c < headers.length; c++) {
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

    for (final v in vacancies) {
      sheet.appendRow([
        TextCellValue(v.id),
        TextCellValue(v.name),
        TextCellValue(stripHtml(v.description)),
        TextCellValue(v.employerName ?? ''),
        TextCellValue(v.areaName ?? ''),
        TextCellValue(v.publishedAt ?? ''),
        TextCellValue(v.alternateUrl ?? ''),
      ]);
    }

    final bytes = excel.save();
    if (bytes == null) throw Exception('Не удалось создать Excel-файл');

    final path = savePath.endsWith('.xlsx') ? savePath : '$savePath.xlsx';
    await File(path).writeAsBytes(bytes);
    return path;
  }
}
