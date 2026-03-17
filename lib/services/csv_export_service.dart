import 'dart:convert';
import 'dart:io';
import 'package:csv/csv.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:path_provider/path_provider.dart';
import '../models/vacancy.dart';

class CsvExportService {
  static String _stripHtml(String html) {
    if (html.isEmpty) return '';
    try {
      final document = html_parser.parse(html);
      return document.body?.text ?? html;
    } catch (_) {
      return html.replaceAll(RegExp(r'<[^>]*>'), '');
    }
  }

  static Future<String> exportToCsv(List<VacancyFull> vacancies) async {
    final rows = <List<dynamic>>[
      ['ID', 'Название вакансии', 'Описание', 'Работодатель', 'Регион', 'Дата публикации', 'Ссылка'],
    ];

    for (final v in vacancies) {
      rows.add([
        v.id,
        v.name,
        _stripHtml(v.description),
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

    final csvWithBom = '\uFEFF$csvData';

    final dir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-')
        .substring(0, 19);
    final file = File('${dir.path}\\hh_vacancies_$timestamp.csv');
    await file.writeAsString(csvWithBom, encoding: utf8);

    return file.path;
  }
}
