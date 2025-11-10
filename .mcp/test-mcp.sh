#!/bin/bash
echo "🧪 Testando configuração MCP..."

# Verificar estrutura
if [ ! -d ".mcp" ]; then
  echo "❌ Diretório .mcp não encontrado"
  exit 1
fi

if [ ! -f ".mcp/config.json" ]; then
  echo "❌ Arquivo .mcp/config.json não encontrado"
  exit 1
fi

# Executar indexação
echo "📊 Executando indexação..."
npm run mcp:index

# Verificar índice gerado
if [ -f ".mcp/context/index.json" ]; then
  echo "✅ Índice MCP criado com sucesso"
  
  # Mostrar estatísticas
  node -e "
    const fs = require('fs');
    const index = JSON.parse(fs.readFileSync('.mcp/context/index.json', 'utf-8'));
    console.log('\n📈 Estatísticas do Índice:');
    console.log('   Modelos:', Object.keys(index.models).length);
    console.log('   Controllers:', Object.keys(index.controllers).length);
    console.log('   Services:', Object.keys(index.services).length);
    console.log('   Componentes:', Object.keys(index.components).length);
  "
else
  echo "❌ Falha ao criar índice MCP"
  exit 1
fi

echo "\n✅ MCP configurado corretamente!"
