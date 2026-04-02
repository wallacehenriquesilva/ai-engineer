# Padroes de Teste — Java

Referencia detalhada de implementacoes de teste para projetos Java/Spring Boot. Complementa o [SKILL.md principal](../SKILL.md).

---

## Nomenclatura

```java
// Formato: metodo_cenario_resultadoEsperado
@Test
void createUser_withValidData_returnsCreatedUser() {}

@Test
void createUser_withDuplicateEmail_throwsConflictException() {}

@Test
void createUser_withEmptyName_throwsValidationException() {}
```

---

## Table-Driven Tests (@ParameterizedTest)

```java
@ParameterizedTest
@MethodSource("cnpjCases")
void validateCNPJ(String description, String input, boolean expected) {
    assertEquals(expected, CnpjValidator.validate(input), description);
}

static Stream<Arguments> cnpjCases() {
    return Stream.of(
        Arguments.of("CNPJ valido com mascara", "11.222.333/0001-81", true),
        Arguments.of("CNPJ valido sem mascara", "11222333000181", true),
        Arguments.of("CNPJ com todos digitos iguais", "11111111111111", false),
        Arguments.of("CNPJ vazio", "", false),
        Arguments.of("CNPJ com letras", "1122233300018a", false)
    );
}
```

---

## Test Fixtures — Builder com Instancio

```java
User testUser = Instancio.of(User.class)
    .set(field(User::getName), "Maria Silva")
    .set(field(User::getEmail), "maria@test.com")
    .create();
```

**Limpeza de dados:** use `@AfterEach` ou transacoes com rollback (`@Transactional`).

---

## Mocks com Mockito

```java
// Mock de dependencia
@Mock
private EmailService emailService;

@InjectMocks
private UserService userService;

@Test
void createUser_sendsWelcomeEmail() {
    when(userRepository.save(any(User.class))).thenReturn(validUser);

    userService.createUser(validUser);

    verify(emailService).sendWelcome(validUser.getEmail());
}
```

### Captura de argumentos (ArgumentCaptor)

```java
@Test
void shouldPublishEventWhenUserCreated() {
    ArgumentCaptor<PublishRequest> captor = ArgumentCaptor.forClass(PublishRequest.class);

    userService.createUser(validUser);

    verify(snsClient).publish(captor.capture());
    PublishRequest published = captor.getValue();
    assertThat(published.topicArn()).contains("user-created");
    assertThat(published.message()).contains(validUser.getEmail());
}
```

---

## Testando Eventos SNS (Spring)

```java
@Test
void shouldPublishEventWhenUserCreated() {
    // Captura a mensagem publicada no SNS
    ArgumentCaptor<PublishRequest> captor = ArgumentCaptor.forClass(PublishRequest.class);

    userService.createUser(validUser);

    verify(snsClient).publish(captor.capture());
    PublishRequest published = captor.getValue();
    assertThat(published.topicArn()).contains("user-created");
    assertThat(published.message()).contains(validUser.getEmail());
}
```

---

## Cobertura

```bash
# Gradle
./gradlew test jacocoTestReport
```

---

## Testando APIs HTTP (MockMvc)

```java
@WebMvcTest(UserController.class)
class UserControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @MockBean
    private UserService userService;

    @Test
    void createUser_withValidData_returns201() throws Exception {
        when(userService.createUser(any())).thenReturn(validUser);

        mockMvc.perform(post("/users")
                .contentType(MediaType.APPLICATION_JSON)
                .header("Authorization", "Bearer " + validToken)
                .content("""
                    {"name":"Maria","email":"maria@test.com"}
                    """))
            .andExpect(status().isCreated())
            .andExpect(jsonPath("$.id").isNotEmpty())
            .andExpect(jsonPath("$.name").value("Maria"));
    }

    @Test
    void createUser_withMissingName_returns400() throws Exception {
        mockMvc.perform(post("/users")
                .contentType(MediaType.APPLICATION_JSON)
                .header("Authorization", "Bearer " + validToken)
                .content("""
                    {"email":"maria@test.com"}
                    """))
            .andExpect(status().isBadRequest());
    }
}
```

---

## Testando Banco de Dados (Testcontainers)

```java
@Testcontainers
@SpringBootTest
class UserRepositoryTest {

    @Container
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:16-alpine")
        .withDatabaseName("testdb")
        .withUsername("test")
        .withPassword("test");

    @DynamicPropertySource
    static void configureProperties(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", postgres::getJdbcUrl);
        registry.add("spring.datasource.username", postgres::getUsername);
        registry.add("spring.datasource.password", postgres::getPassword);
    }

    @Autowired
    private UserRepository userRepository;

    @Test
    void save_withValidUser_persistsSuccessfully() {
        User user = testUser();
        userRepository.save(user);

        Optional<User> found = userRepository.findByEmail(user.getEmail());
        assertThat(found).isPresent();
        assertThat(found.get().getName()).isEqualTo(user.getName());
    }

    @Test
    void save_withDuplicateEmail_throwsException() {
        User user1 = testUser();
        User user2 = testUser();
        user2.setEmail(user1.getEmail());

        userRepository.save(user1);

        assertThrows(DataIntegrityViolationException.class,
            () -> userRepository.save(user2));
    }
}
```

---

## Ferramentas e bibliotecas

| Ferramenta | Uso |
|---|---|
| JUnit 5 | Framework de testes |
| `@ParameterizedTest` / `@MethodSource` | Table-driven tests |
| Mockito | Mocking e verificacao |
| MockMvc | Testes de controllers HTTP |
| Testcontainers | Banco de dados real em container |
| Instancio | Geracao de dados de teste |
| `@Transactional` | Rollback automatico apos teste |
| `@AfterEach` | Limpeza manual |
