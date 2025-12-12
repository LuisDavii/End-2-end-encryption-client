## Integracao do Projeto

Este projeto funciona em conjunto com o Servidor (Backend). Para ver o codigo do servidor Python, acesse o repositorio complementar:

> 🔗 **[Acesse o Repositório do Cliente Aqui](https://github.com/LuisDavii/End-2-end-encryption-server)**

# Cliente de Chat Seguro 

Este é o aplicativo móvel desenvolvido em **Flutter** para o projeto de Criptografia Ponta-a-Ponta. Ele atua como a interface do usuário segura, realizando todas as operações de criptografia e descriptografia localmente antes que os dados sejam enviados à rede.

## Descrição

O aplicativo permite a troca de mensagens em tempo real com garantia de privacidade absoluta. O servidor atua apenas como um transportador de dados cifrados, sem capacidade técnica para ler o conteúdo das conversas.

## Funcionalidades de Seguranca

Este cliente implementa os requisitos rigorosos de segurança definidos no projeto:

1.  **Criptografia Ponta-a-Ponta (E2EE):**
    * As mensagens são cifradas no dispositivo usando **AES-CBC (256 bits) + HMAC-SHA256**.
    * O servidor atua apenas como roteador e não possui as chaves para ler o conteúdo.
2.  **Autenticacao Mutua:**
    * Os clientes realizam um handshake direto e trocam desafios assinados digitalmente (**Ed25519**) para garantir a identidade do interlocutor e evitar ataques *Man-in-the-Middle*.
3.  **Armazenamento Local Seguro:**
    * O histórico de conversas é salvo em um banco de dados **SQLite** local.
    * O conteúdo do banco é cifrado com **AES-GCM**.
    * A chave de encriptação do banco é protegida pelo hardware de segurança do dispositivo (**Keystore** no Android / **Keychain** no iOS).
4.  **Login Hibrido:**
    * **Senha (Argon2):** Usada apenas no primeiro acesso em um novo dispositivo.
    * **Desafio-Resposta (Assinatura):** Logins subsequentes usam a chave privada armazenada localmente, sem trafegar a senha pela rede.

## Pre-requisitos

Para rodar este projeto, você precisa ter instalado:

* **Flutter SDK** (Versão 3.0 ou superior).
* **Android Studio** ou **VS Code** (com extensões Flutter/Dart).
* Um **Emulador Android/iOS** ou um **Dispositivo Fisico**.
* **Requisito de Sistema:** Android Min SDK 18 ou superior.

## Instalacao

1.  **Clonar o repositorio** (ou extrair os arquivos na pasta do projeto).

2.  **Baixar as dependencias:**
    Abra o terminal na pasta raiz do projeto (`client_chat`) e execute:
    ```bash
    flutter pub get
    ```

## Configuracao de Rede (Importante!)

Como o aplicativo se conecta a um servidor WebSocket (Python), é necessário configurar o endereço IP correto dependendo de como você está executando o app.

### 1. Identifique o seu cenario:

* **Emulador Android:** O endereço do seu computador (localhost) é acessível via `10.0.2.2`.
* **Emulador iOS:** O endereço é `localhost` ou `127.0.0.1`.
* **Dispositivo Fisico (Celular real):** Você deve usar o **endereço IPv4 da sua máquina** na rede local (ex: `192.168.1.15`). *Certifique-se de que o firewall do Windows/Linux permite conexões na porta 12345.*

### 2. Atualize o Endereco no Codigo:

Você precisa alterar a URL de conexão (`ws://...:12345`) nos arquivos onde a conexão é iniciada. Procure por `connectAndHandshake` ou `WebSocketChannel.connect` nos seguintes arquivos:

* `lib/screens/login_page.dart`
* `lib/screens/register_page.dart`
* `lib/screens/welcome_page.dart`
* `lib/screens/splash_page.dart`

**Exemplo de alteracao:**

```dart
// Para Emulador Android (Padrao)
await secureChannel.connectAndHandshake('ws://10.0.2.2:12345');

// Para Dispositivo Fisico (Exemplo)
// await secureChannel.connectAndHandshake('ws://192.168.0.105:12345');
```

## Como Rodar

Certifique-se de que o **Servidor Python esta rodando** antes de iniciar o aplicativo.

### Via Terminal

Conecte seu dispositivo ou inicie o emulador e execute:

```bash
flutter run
```
### Comandos Uteis para Debug
Se encontrar erros de build, cache ou dependências, use esta sequência para limpar e reconstruir o projeto:
```bash
fflutter clean
flutter pub get
flutter run
```
## Estrutura e Bibliotecas Principais

O projeto utiliza as seguintes bibliotecas para atender aos requisitos de seguranca:

* **`cryptography`**: Biblioteca robusta utilizada para todas as primitivas criptograficas (X25519 para troca de chaves, Ed25519 para assinaturas, AES-GCM/CBC para cifragem e HKDF para derivacao).
* **`flutter_secure_storage`**: Utilizada para armazenar a chave mestra do banco de dados de forma segura no Keystore (Android) ou Keychain (iOS).
* **`sqflite`**: Gerenciamento do banco de dados SQLite local, onde o historico e salvo de forma cifrada.
* **`shared_preferences`**: Armazenamento simples para persistir o estado de login e o nome do ultimo usuario ("Lembrar de mim").
* **`web_socket_channel`**: Para comunicacao em tempo real com o servidor via WebSocket.
