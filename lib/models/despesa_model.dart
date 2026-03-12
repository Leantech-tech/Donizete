class Despesa {
  final String? id;
  final DateTime? createdAt;
  final String beneficiario;
  final String referente;
  final double valor;
  final DateTime data;
  final bool isExcluido;

  Despesa({
    this.id,
    this.createdAt,
    required this.beneficiario,
    required this.referente,
    required this.valor,
    required this.data,
    this.isExcluido = false,
  });

  factory Despesa.fromJson(Map<String, dynamic> json) {
    return Despesa(
      id: json['id']?.toString(),
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at']) : null,
      beneficiario: json['beneficiario'] ?? '',
      referente: json['referente'] ?? '',
      valor: double.tryParse(json['valor']?.toString() ?? '0') ?? 0,
      data: DateTime.tryParse(json['data'] ?? '') ?? DateTime.now(),
      isExcluido: json['is_excluido'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'beneficiario': beneficiario,
      'referente': referente,
      'valor': valor,
      'data': data.toIso8601String().split('T')[0],
      'is_excluido': isExcluido,
    };
  }

  Despesa copyWith({
    String? id,
    DateTime? createdAt,
    String? beneficiario,
    String? referente,
    double? valor,
    DateTime? data,
    bool? isExcluido,
  }) {
    return Despesa(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      beneficiario: beneficiario ?? this.beneficiario,
      referente: referente ?? this.referente,
      valor: valor ?? this.valor,
      data: data ?? this.data,
      isExcluido: isExcluido ?? this.isExcluido,
    );
  }
}
