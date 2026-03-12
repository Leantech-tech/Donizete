class Cliente {
  final String? id;
  final String tipoCliente;
  final String razaoSocial;
  final String? contato;
  final String? fantasia;
  final String? cnpjCpf;
  final String? cep;
  final String? logradouro;
  final String? bairro;
  final String? numero;
  final String? complemento;
  final String? cidade;
  final String? telefone;
  final bool isAtivo;
  final bool isGeloDoPorto;
  final double? valorGeloDoPorto;
  final bool isExcluido;

  Cliente({
    this.id,
    required this.tipoCliente,
    required this.razaoSocial,
    this.contato,
    this.fantasia,
    this.cnpjCpf,
    this.cep,
    this.logradouro,
    this.bairro,
    this.numero,
    this.complemento,
    this.cidade,
    this.telefone,
    this.isAtivo = true,
    this.isGeloDoPorto = false,
    this.valorGeloDoPorto,
    this.isExcluido = false,
  });

  factory Cliente.fromJson(Map<String, dynamic> json) {
    return Cliente(
      id: json['id']?.toString(),
      tipoCliente: json['tipo_cliente'] ?? 'PF',
      razaoSocial: json['razao_social'] ?? '',
      contato: json['contato'],
      fantasia: json['fantasia'],
      cnpjCpf: json['cnpj_cpf']?.toString(),
      cep: json['cep']?.toString(),
      logradouro: json['logradouro'],
      bairro: json['bairro'],
      numero: json['numero'],
      complemento: json['complemento'],
      cidade: json['cidade'],
      telefone: json['telefone']?.toString(),
      isAtivo: json['is_ativo'] ?? true,
      isGeloDoPorto: json['is_gelo_do_porto'] ?? false,
      valorGeloDoPorto: json['valor_gelo_do_porto'] != null ? (json['valor_gelo_do_porto'] as num).toDouble() : null,
      isExcluido: json['is_excluido'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'tipo_cliente': tipoCliente,
      'razao_social': razaoSocial,
      'contato': contato,
      'fantasia': fantasia,
      'cnpj_cpf': cnpjCpf?.replaceAll(RegExp(r'\D'), ''),
      'cep': cep?.replaceAll(RegExp(r'\D'), ''),
      'logradouro': logradouro,
      'bairro': bairro,
      'numero': numero,
      'complemento': complemento,
      'cidade': cidade,
      'telefone': telefone?.replaceAll(RegExp(r'\D'), ''),
      'is_ativo': isAtivo,
      'is_gelo_do_porto': isGeloDoPorto,
      'valor_gelo_do_porto': valorGeloDoPorto,
      'is_excluido': isExcluido,
    };
  }

  Cliente copyWith({
    String? id,
    String? tipoCliente,
    String? razaoSocial,
    String? contato,
    String? fantasia,
    String? cnpjCpf,
    String? cep,
    String? logradouro,
    String? bairro,
    String? numero,
    String? complemento,
    String? cidade,
    String? telefone,
    bool? isAtivo,
    bool? isGeloDoPorto,
    bool? isExcluido,
  }) {
    return Cliente(
      id: id ?? this.id,
      tipoCliente: tipoCliente ?? this.tipoCliente,
      razaoSocial: razaoSocial ?? this.razaoSocial,
      contato: contato ?? this.contato,
      fantasia: fantasia ?? this.fantasia,
      cnpjCpf: cnpjCpf ?? this.cnpjCpf,
      cep: cep ?? this.cep,
      logradouro: logradouro ?? this.logradouro,
      bairro: bairro ?? this.bairro,
      numero: numero ?? this.numero,
      complemento: complemento ?? this.complemento,
      cidade: cidade ?? this.cidade,
      telefone: telefone ?? this.telefone,
      isAtivo: isAtivo ?? this.isAtivo,
      isGeloDoPorto: isGeloDoPorto ?? this.isGeloDoPorto,
      valorGeloDoPorto: valorGeloDoPorto ?? this.valorGeloDoPorto,
      isExcluido: isExcluido ?? this.isExcluido,
    );
  }
}
