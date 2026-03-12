class LancamentoCabecalho {
  final String? id;
  final String clienteId;
  final String? clienteNome;
  final DateTime dtEmissao;
  final String? tipoPagamento;
  final double vrTotalVenda;
  final double vrTotalCusto;
  final double vrTotalLucro;
  final bool isExcluido;

  LancamentoCabecalho({
    this.id,
    required this.clienteId,
    this.clienteNome,
    required this.dtEmissao,
    this.tipoPagamento,
    this.vrTotalVenda = 0,
    this.vrTotalCusto = 0,
    this.vrTotalLucro = 0,
    this.isExcluido = false,
  });

  factory LancamentoCabecalho.fromJson(Map<String, dynamic> json) {
    return LancamentoCabecalho(
      id: json['id']?.toString(),
      clienteId: json['cliente_id']?.toString() ?? '',
      clienteNome: json['clientes']?['razao_social'],
      dtEmissao: DateTime.tryParse(json['dt_emissao'] ?? '') ?? DateTime.now(),
      tipoPagamento: json['tipo_pagamento'],
      vrTotalVenda: double.tryParse(json['vr_total_venda']?.toString() ?? '0') ?? 0,
      vrTotalCusto: double.tryParse(json['vr_total_custo']?.toString() ?? '0') ?? 0,
      vrTotalLucro: double.tryParse(json['vr_total_lucro']?.toString() ?? '0') ?? 0,
      isExcluido: json['is_excluido'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'cliente_id': clienteId,
      'dt_emissao': dtEmissao.toIso8601String().split('T')[0],
      'tipo_pagamento': tipoPagamento,
      'vr_total_venda': vrTotalVenda,
      'vr_total_custo': vrTotalCusto,
      'vr_total_lucro': vrTotalLucro,
      'is_excluido': isExcluido,
    };
  }
}

class LancamentoItem {
  final String? id;
  final String? cabecalhoId;
  final String produtoId;
  final String? produtoNome;
  final double vrCusto;
  final double vrVenda;
  final double vrDesconto;
  final int quantidade;

  LancamentoItem({
    this.id,
    this.cabecalhoId,
    required this.produtoId,
    this.produtoNome,
    this.vrCusto = 0,
    this.vrVenda = 0,
    this.vrDesconto = 0,
    this.quantidade = 1,
  });

  factory LancamentoItem.fromJson(Map<String, dynamic> json) {
    final produtos = json['produtos'];
    String? nomeProduto;
    if (produtos is List && produtos.isNotEmpty) {
      nomeProduto = produtos[0]['nome'];
    } else if (produtos is Map) {
      nomeProduto = produtos['nome'];
    }

    return LancamentoItem(
      id: json['id']?.toString(),
      cabecalhoId: json['cabecalho_id']?.toString(),
      produtoId: json['produto_id']?.toString() ?? '',
      produtoNome: nomeProduto,
      vrCusto: double.tryParse(json['vr_custo']?.toString() ?? '0') ?? 0,
      vrVenda: double.tryParse(json['vr_venda']?.toString() ?? '0') ?? 0,
      vrDesconto: double.tryParse(json['vr_desconto']?.toString() ?? '0') ?? 0,
      quantidade: int.tryParse(json['quantidade']?.toString() ?? '1') ?? 1,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      if (cabecalhoId != null) 'cabecalho_id': cabecalhoId,
      'produto_id': produtoId,
      'vr_custo': vrCusto,
      'vr_venda': vrVenda,
      'vr_desconto': vrDesconto,
      'quantidade': quantidade,
    };
  }

  double get subtotal => (vrVenda - vrDesconto) * quantidade;
  double get custoTotal => vrCusto * quantidade;
}
