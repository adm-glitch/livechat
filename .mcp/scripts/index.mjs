import fs from 'fs-extra';
import path from 'path';
import { globSync } from 'glob';

class ChatwootMCPIndexer {
  constructor() {
    this.projectRoot = process.cwd();
    this.index = {
      metadata: {
        project: 'chatwoot-crm-fork',
        indexed_at: new Date().toISOString(),
        version: '1.0.0'
      },
      models: {},
      controllers: {},
      services: {},
      components: {},
      routes: null,
      schema: null,
      conventions: {
        rails: {
          version: '7.0',
          style: 'snake_case',
          test_framework: 'rspec'
        },
        vue: {
          version: '3',
          style: 'composition-api',
          naming: 'PascalCase'
        }
      }
    };
  }

  async run() {
    console.log('🔍 Iniciando indexação do projeto Chatwoot...\n');
    
    try {
      await this.indexModels();
      await this.indexControllers();
      await this.indexServices();
      await this.indexVueComponents();
      await this.extractRoutes();
      await this.extractSchema();
      await this.saveIndex();
      
      console.log('\n✅ Indexação concluída com sucesso!');
      this.printSummary();
    } catch (error) {
      console.error('❌ Erro durante indexação:', error.message);
      process.exit(1);
    }
  }

  async indexModels() {
    console.log('📊 Indexando modelos Rails...');
    const modelFiles = globSync('app/models/**/*.rb', { cwd: this.projectRoot });
    
    for (const file of modelFiles) {
      if (file.includes('/concerns/')) continue;
      
      const content = await fs.readFile(path.join(this.projectRoot, file), 'utf-8');
      const modelName = path.basename(file, '.rb');
      
      this.index.models[modelName] = {
        file,
        associations: this.extractAssociations(content),
        validations: this.extractValidations(content),
        scopes: this.extractScopes(content),
        callbacks: this.extractCallbacks(content)
      };
    }
    
    console.log(`   ✓ ${Object.keys(this.index.models).length} modelos indexados`);
  }

  extractAssociations(content) {
    const associations = [];
    const regex = /(belongs_to|has_many|has_one|has_and_belongs_to_many)\s+:(\w+)/g;
    let match;
    
    while ((match = regex.exec(content)) !== null) {
      associations.push({
        type: match[1],
        name: match[2]
      });
    }
    
    return associations;
  }

  extractValidations(content) {
    const validations = [];
    const regex = /validates?\s+:(\w+)/g;
    let match;
    
    while ((match = regex.exec(content)) !== null) {
      validations.push(match[1]);
    }
    
    return validations;
  }

  extractScopes(content) {
    const scopes = [];
    const regex = /scope\s+:(\w+)/g;
    let match;
    
    while ((match = regex.exec(content)) !== null) {
      scopes.push(match[1]);
    }
    
    return scopes;
  }

  extractCallbacks(content) {
    const callbacks = [];
    const callbackTypes = [
      'before_validation', 'after_validation',
      'before_save', 'after_save',
      'before_create', 'after_create',
      'before_update', 'after_update'
    ];
    
    for (const type of callbackTypes) {
      const regex = new RegExp(`${type}\\s+:(\\w+)`, 'g');
      let match;
      
      while ((match = regex.exec(content)) !== null) {
        callbacks.push({
          type,
          method: match[1]
        });
      }
    }
    
    return callbacks;
  }

  async indexControllers() {
    console.log('🎮 Indexando controllers...');
    const controllerFiles = globSync('app/controllers/**/*.rb', { cwd: this.projectRoot });
    
    for (const file of controllerFiles) {
      const content = await fs.readFile(path.join(this.projectRoot, file), 'utf-8');
      const controllerName = path.basename(file, '.rb');
      
      this.index.controllers[controllerName] = {
        file,
        actions: this.extractActions(content)
      };
    }
    
    console.log(`   ✓ ${Object.keys(this.index.controllers).length} controllers indexados`);
  }

  extractActions(content) {
    const actions = [];
    const regex = /def\s+(\w+)/g;
    let match;
    
    while ((match = regex.exec(content)) !== null) {
      const action = match[1];
      if (!action.startsWith('_') && action !== 'initialize') {
        actions.push(action);
      }
    }
    
    return actions;
  }

  async indexServices() {
    console.log('⚙️  Indexando services...');
    const serviceFiles = globSync('app/services/**/*.rb', { cwd: this.projectRoot });
    
    for (const file of serviceFiles) {
      const content = await fs.readFile(path.join(this.projectRoot, file), 'utf-8');
      const serviceName = path.basename(file, '.rb');
      
      this.index.services[serviceName] = {
        file,
        methods: this.extractMethods(content)
      };
    }
    
    console.log(`   ✓ ${Object.keys(this.index.services).length} services indexados`);
  }

  extractMethods(content) {
    const methods = [];
    const regex = /def\s+(self\.)?(\w+)/g;
    let match;
    
    while ((match = regex.exec(content)) !== null) {
      methods.push({
        name: match[2],
        is_class_method: !!match[1]
      });
    }
    
    return methods;
  }

  async indexVueComponents() {
    console.log('🖼️  Indexando componentes Vue...');
    const componentFiles = globSync('app/javascript/**/*.vue', { cwd: this.projectRoot });
    
    for (const file of componentFiles) {
      const content = await fs.readFile(path.join(this.projectRoot, file), 'utf-8');
      const componentName = path.basename(file, '.vue');
      
      this.index.components[componentName] = {
        file,
        props: this.extractVueProps(content),
        emits: this.extractVueEmits(content)
      };
    }
    
    console.log(`   ✓ ${Object.keys(this.index.components).length} componentes indexados`);
  }

  extractVueProps(content) {
    const props = [];
    const regex = /props:\s*{\s*([^}]+)}/s;
    const match = content.match(regex);
    
    if (match) {
      const propsContent = match[1];
      const propRegex = /(\w+):/g;
      let propMatch;
      
      while ((propMatch = propRegex.exec(propsContent)) !== null) {
        props.push(propMatch[1]);
      }
    }
    
    return props;
  }

  extractVueEmits(content) {
    const emits = new Set();
    const regex = /\$emit\(['"](\w+)['"]/g;
    let match;
    
    while ((match = regex.exec(content)) !== null) {
      emits.add(match[1]);
    }
    
    return Array.from(emits);
  }

  async extractRoutes() {
    console.log('🛣️  Extraindo rotas...');
    const routesFile = path.join(this.projectRoot, 'config/routes.rb');
    
    if (await fs.pathExists(routesFile)) {
      this.index.routes = await fs.readFile(routesFile, 'utf-8');
      console.log('   ✓ Rotas extraídas');
    }
  }

  async extractSchema() {
    console.log('🗄️  Extraindo schema do banco...');
    const schemaFile = path.join(this.projectRoot, 'db/schema.rb');
    
    if (await fs.pathExists(schemaFile)) {
      this.index.schema = await fs.readFile(schemaFile, 'utf-8');
      console.log('   ✓ Schema extraído');
    }
  }

  async saveIndex() {
    const indexPath = path.join(this.projectRoot, '.mcp/context/index.json');
    await fs.ensureDir(path.dirname(indexPath));
    await fs.writeJson(indexPath, this.index, { spaces: 2 });
    console.log(`\n💾 Índice salvo em: ${indexPath}`);
  }

  printSummary() {
    console.log('\n📊 Resumo da Indexação:');
    console.log(`   • ${Object.keys(this.index.models).length} modelos`);
    console.log(`   • ${Object.keys(this.index.controllers).length} controllers`);
    console.log(`   • ${Object.keys(this.index.services).length} services`);
    console.log(`   • ${Object.keys(this.index.components).length} componentes Vue`);
    console.log(`   • Schema: ${this.index.schema ? 'Disponível' : 'Não encontrado'}`);
    console.log(`   • Rotas: ${this.index.routes ? 'Disponível' : 'Não encontrado'}`);
  }
}

// Executar indexador
const indexer = new ChatwootMCPIndexer();
indexer.run().catch(console.error);
