#!/usr/bin/env node

import fs from 'fs-extra';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

class ChatwootMCPServer {
  constructor() {
    this.projectRoot = path.resolve(__dirname, '../..');
    this.indexPath = path.join(this.projectRoot, '.mcp/context/index.json');
    this.configPath = path.join(this.projectRoot, '.mcp/config.json');
    this.index = null;
    this.config = null;
  }

  async init() {
    // Load index
    if (await fs.pathExists(this.indexPath)) {
      this.index = await fs.readJson(this.indexPath);
    } else {
      throw new Error('Index not found. Run: npm run mcp:index');
    }

    // Load config
    if (await fs.pathExists(this.configPath)) {
      this.config = await fs.readJson(this.configPath);
    }

    console.error('✅ Chatwoot MCP Server initialized');
    console.error(`   Models: ${Object.keys(this.index.models).length}`);
    console.error(`   Controllers: ${Object.keys(this.index.controllers).length}`);
    console.error(`   Services: ${Object.keys(this.index.services).length}`);
    console.error(`   Components: ${Object.keys(this.index.components).length}`);
  }

  // MCP Protocol Methods
  async handleRequest(request) {
    const { method, params } = request;

    try {
      let result;

      switch (method) {
        case 'initialize':
          result = {
            protocolVersion: '2024-11-05',
            capabilities: {
              tools: {},
              resources: {}
            },
            serverInfo: {
              name: 'chatwoot-context',
              version: '1.0.0'
            }
          };
          break;

        case 'tools/list':
          result = this.listTools();
          break;
        
        case 'tools/call':
          result = await this.callTool(params.name, params.arguments);
          break;

        case 'resources/list':
          result = this.listResources();
          break;

        case 'resources/read':
          result = await this.readResource(params.uri);
          break;

        default:
          throw new Error(`Unknown method: ${method}`);
      }

      return {
        jsonrpc: '2.0',
        id: request.id,
        result
      };
    } catch (error) {
      return {
        jsonrpc: '2.0',
        id: request.id,
        error: {
          code: -32603,
          message: error.message
        }
      };
    }
  }

  listTools() {
    return {
      tools: [
        {
          name: 'get_project_context',
          description: 'Get overall project context and guidelines',
          inputSchema: {
            type: 'object',
            properties: {}
          }
        },
        {
          name: 'search_models',
          description: 'Search for Rails models by name or pattern',
          inputSchema: {
            type: 'object',
            properties: {
              query: { type: 'string', description: 'Search query' }
            },
            required: ['query']
          }
        },
        {
          name: 'get_model_details',
          description: 'Get detailed information about a specific model',
          inputSchema: {
            type: 'object',
            properties: {
              modelName: { type: 'string', description: 'Model name (snake_case)' }
            },
            required: ['modelName']
          }
        },
        {
          name: 'get_lgpd_requirements',
          description: 'Check LGPD requirements for a field or action',
          inputSchema: {
            type: 'object',
            properties: {
              field: { type: 'string', description: 'Field name to check' }
            },
            required: ['field']
          }
        },
        {
          name: 'list_crm_models',
          description: 'List all CRM-specific models',
          inputSchema: {
            type: 'object',
            properties: {}
          }
        },
        {
          name: 'search_controllers',
          description: 'Search for controllers',
          inputSchema: {
            type: 'object',
            properties: {
              query: { type: 'string', description: 'Search query' }
            },
            required: ['query']
          }
        },
        {
          name: 'get_routes',
          description: 'Get Rails routes configuration',
          inputSchema: {
            type: 'object',
            properties: {}
          }
        },
        {
          name: 'get_schema',
          description: 'Get database schema',
          inputSchema: {
            type: 'object',
            properties: {}
          }
        }
      ]
    };
  }

  async callTool(name, args) {
    switch (name) {
      case 'get_project_context':
        return this.getProjectContext();
      
      case 'search_models':
        return this.searchModels(args.query);
      
      case 'get_model_details':
        return this.getModelDetails(args.modelName);
      
      case 'get_lgpd_requirements':
        return this.getLGPDRequirements(args.field);
      
      case 'list_crm_models':
        return this.listCRMModels();
      
      case 'search_controllers':
        return this.searchControllers(args.query);
      
      case 'get_routes':
        return this.getRoutes();
      
      case 'get_schema':
        return this.getSchema();
      
      default:
        throw new Error(`Unknown tool: ${name}`);
    }
  }

  getProjectContext() {
    return {
      content: [{
        type: 'text',
        text: JSON.stringify({
          name: this.config?.name || 'chatwoot-crm-fork',
          description: this.config?.description,
          metadata: this.index.metadata,
          conventions: this.index.conventions,
          guidelines: this.config?.project_guidelines,
          stats: {
            models: Object.keys(this.index.models).length,
            controllers: Object.keys(this.index.controllers).length,
            services: Object.keys(this.index.services).length,
            components: Object.keys(this.index.components).length
          }
        }, null, 2)
      }]
    };
  }

  searchModels(query) {
    const matches = Object.entries(this.index.models)
      .filter(([name]) => name.toLowerCase().includes(query.toLowerCase()))
      .map(([name, data]) => ({
        name,
        file: data.file,
        associations: data.associations.length,
        validations: data.validations.length
      }));

    return {
      content: [{
        type: 'text',
        text: JSON.stringify(matches, null, 2)
      }]
    };
  }

  getModelDetails(modelName) {
    const model = this.index.models[modelName];
    if (!model) {
      throw new Error(`Model not found: ${modelName}`);
    }

    return {
      content: [{
        type: 'text',
        text: JSON.stringify(model, null, 2)
      }]
    };
  }

  getLGPDRequirements(field) {
    const lgpd = this.config?.project_guidelines?.lgpd_requirements;
    if (!lgpd) {
      return { content: [{ type: 'text', text: 'LGPD requirements not configured' }] };
    }

    const requirements = {
      field,
      encrypt: lgpd.always_encrypt?.includes(field),
      audit: lgpd.always_audit?.some(audit => audit.includes(field)),
      consent: lgpd.consent_required_for?.some(item => field.includes(item))
    };

    return {
      content: [{
        type: 'text',
        text: JSON.stringify(requirements, null, 2)
      }]
    };
  }

  listCRMModels() {
    const crmModels = this.config?.project_guidelines?.crm_models || [];
    const models = crmModels.map(name => {
      const snakeCase = name.replace(/([A-Z])/g, '_$1').toLowerCase().replace(/^_/, '');
      return {
        name,
        snakeCase,
        details: this.index.models[snakeCase]
      };
    });

    return {
      content: [{
        type: 'text',
        text: JSON.stringify(models, null, 2)
      }]
    };
  }

  searchControllers(query) {
    const matches = Object.entries(this.index.controllers)
      .filter(([name]) => name.toLowerCase().includes(query.toLowerCase()))
      .map(([name, data]) => ({
        name,
        file: data.file,
        actions: data.actions
      }));

    return {
      content: [{
        type: 'text',
        text: JSON.stringify(matches, null, 2)
      }]
    };
  }

  getRoutes() {
    return {
      content: [{
        type: 'text',
        text: this.index.routes || 'Routes not available'
      }]
    };
  }

  getSchema() {
    return {
      content: [{
        type: 'text',
        text: this.index.schema || 'Schema not available'
      }]
    };
  }

  listResources() {
    return {
      resources: [
        {
          uri: 'chatwoot://index',
          name: 'Full Project Index',
          mimeType: 'application/json'
        },
        {
          uri: 'chatwoot://config',
          name: 'Project Configuration',
          mimeType: 'application/json'
        }
      ]
    };
  }

  async readResource(uri) {
    if (uri === 'chatwoot://index') {
      return {
        contents: [{
          uri,
          mimeType: 'application/json',
          text: JSON.stringify(this.index, null, 2)
        }]
      };
    }

    if (uri === 'chatwoot://config') {
      return {
        contents: [{
          uri,
          mimeType: 'application/json',
          text: JSON.stringify(this.config, null, 2)
        }]
      };
    }

    throw new Error(`Unknown resource: ${uri}`);
  }

  async start() {
    await this.init();

    // Send server info immediately on startup
    const serverInfo = {
      jsonrpc: '2.0',
      method: 'server/info',
      params: {
        protocolVersion: '2024-11-05',
        capabilities: {
          tools: {},
          resources: {}
        },
        serverInfo: {
          name: 'chatwoot-context',
          version: '1.0.0'
        }
      }
    };

    // Handle JSONRPC over stdio
    let buffer = '';

    process.stdin.setEncoding('utf8');
    
    process.stdin.on('data', async (chunk) => {
      buffer += chunk;
      
      // Look for complete JSON-RPC messages
      let newlineIndex;
      while ((newlineIndex = buffer.indexOf('\n')) !== -1) {
        const line = buffer.slice(0, newlineIndex).trim();
        buffer = buffer.slice(newlineIndex + 1);

        if (line) {
          try {
            const request = JSON.parse(line);
            
            // Handle initialization
            if (request.method === 'initialize') {
              const response = {
                jsonrpc: '2.0',
                id: request.id,
                result: {
                  protocolVersion: '2024-11-05',
                  capabilities: {
                    tools: {},
                    resources: {}
                  },
                  serverInfo: {
                    name: 'chatwoot-context',
                    version: '1.0.0'
                  }
                }
              };
              process.stdout.write(JSON.stringify(response) + '\n');
            } else {
              const response = await this.handleRequest(request);
              process.stdout.write(JSON.stringify(response) + '\n');
            }
          } catch (error) {
            console.error('Error processing request:', error);
            if (line.includes('"id"')) {
              try {
                const req = JSON.parse(line);
                process.stdout.write(JSON.stringify({
                  jsonrpc: '2.0',
                  id: req.id,
                  error: {
                    code: -32603,
                    message: error.message
                  }
                }) + '\n');
              } catch {}
            }
          }
        }
      }
    });

    process.stdin.on('end', () => {
      console.error('MCP Server shutting down');
      process.exit(0);
    });

    // Keep process alive
    process.stdin.resume();
  } 
}

// Start server
const server = new ChatwootMCPServer();
server.start().catch(error => {
  console.error('Failed to start MCP server:', error);
  process.exit(1);
});
