class VacancyBrief {
  final String id;
  final String name;
  final String? alternateUrl;
  final String? publishedAt;

  VacancyBrief({
    required this.id,
    required this.name,
    this.alternateUrl,
    this.publishedAt,
  });

  factory VacancyBrief.fromJson(Map<String, dynamic> json) {
    return VacancyBrief(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      alternateUrl: json['alternate_url']?.toString(),
      publishedAt: json['published_at']?.toString(),
    );
  }
}

class VacancyFull {
  final String id;
  final String name;
  final String description;
  final String? alternateUrl;
  final String? publishedAt;
  final String? employerName;
  final String? areaName;

  VacancyFull({
    required this.id,
    required this.name,
    required this.description,
    this.alternateUrl,
    this.publishedAt,
    this.employerName,
    this.areaName,
  });

  factory VacancyFull.fromJson(Map<String, dynamic> json) {
    final employer = json['employer'] as Map<String, dynamic>?;
    final area = json['area'] as Map<String, dynamic>?;
    return VacancyFull(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      alternateUrl: json['alternate_url']?.toString(),
      publishedAt: json['published_at']?.toString(),
      employerName: employer?['name']?.toString(),
      areaName: area?['name']?.toString(),
    );
  }
}

enum SearchStatus {
  idle,
  gettingToken,
  estimating,
  collectingIds,
  fetchingDetails,
  done,
  error,
  paused,
}

class SearchState {
  final SearchStatus status;
  final int totalExpected;
  final int totalIdsCollected;
  final int totalDetailsFetched;
  final String message;
  final String? errorMessage;
  final List<VacancyFull> vacancies;

  const SearchState({
    this.status = SearchStatus.idle,
    this.totalExpected = 0,
    this.totalIdsCollected = 0,
    this.totalDetailsFetched = 0,
    this.message = '',
    this.errorMessage,
    this.vacancies = const [],
  });

  SearchState copyWith({
    SearchStatus? status,
    int? totalExpected,
    int? totalIdsCollected,
    int? totalDetailsFetched,
    String? message,
    String? errorMessage,
    List<VacancyFull>? vacancies,
  }) {
    return SearchState(
      status: status ?? this.status,
      totalExpected: totalExpected ?? this.totalExpected,
      totalIdsCollected: totalIdsCollected ?? this.totalIdsCollected,
      totalDetailsFetched: totalDetailsFetched ?? this.totalDetailsFetched,
      message: message ?? this.message,
      errorMessage: errorMessage ?? this.errorMessage,
      vacancies: vacancies ?? this.vacancies,
    );
  }

  double get idsProgress =>
      totalExpected > 0 ? (totalIdsCollected / totalExpected).clamp(0.0, 1.0) : 0.0;

  double get detailsProgress =>
      totalIdsCollected > 0
          ? (totalDetailsFetched / totalIdsCollected).clamp(0.0, 1.0)
          : 0.0;
}
