class Produto {
  final String? id;
  final String nome;
  final String? codigoInterno;
  final double vrCusto;
  final double margem;
  final double vrVenda;
  final bool isAtivo;
  final bool isExcluido;

  Produto({
    this.id,
    required this.nome,
    this.codigoInterno,
    this.vrCusto = 0,
    this.margem = 0,
    this.vrVenda = 0,
    this.isAtivo = true,
    this.isExcluido = false,
  });

  factory Produto.fromJson(Map<String, dynamic> json) {
    return Produto(
      id: json['id']?.toString(),
      nome: json['nome'] ?? '',
      codigoInterno: json['codigo_interno'],
      vrCusto: double.tryParse(json['vr_custo']?.toString() ?? '0') ?? 0,
      margem: double.tryParse(json['margem']?.toString() ?? '0') ?? 0,
      vrVenda: double.tryParse(json['vr_venda']?.toString() ?? '0') ?? 0,
      isAtivo: json['is_ativo'] ?? true,
      isExcluido: json['is_excluido'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'nome': nome,
      'codigo_interno': codigoInterno,
      'vr_custo': vrCusto,
      'margem': margem,
      'vr_venda': vrVenda,
      'is_ativo': isAtivo,
      'is_excluido': isExcluido,
    };
  }

  Produto copyWith({
    String? id,
    String? nome,
    String? codigoInterno,
    double? vrCusto,
    double? margem,
    double? vrVenda,
    bool? isAtivo,
    bool? isExcluido,
  }) {
    return Produto(
      id: id ?? this.id,
      nome: nome ?? this.nome,
      codigoInterno: codigoInterno ?? this.codigoInterno,
      vrCusto: vrCusto ?? this.vrCusto,
      margem: margem ?? this.margem,
      vrVenda: vrVenda ?? this.vrVenda,
      isAtivo: isAtivo ?? this.isAtivo,
      isExcluido: isExcluido ?? this.isExcluido,
    );
  }

  /// Calcula o preço de venda baseado no custo e margem
  static double calcularVenda(double custo, double margem) {
    return custo + (custo * (margem / 100));
  }

  /// Calcula a margem baseado no custo e preço de venda
  static double calcularMargem(double custo, double venda) {
    if (custo <= 0) return 0;
    return ((venda - custo) / custo) * 100;
  }
}
