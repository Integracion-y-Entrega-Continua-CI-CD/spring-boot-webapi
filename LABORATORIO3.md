# Laboratorio 3 — Integración de Pruebas Automatizadas al Pipeline

Proyecto: `com.cicd:webapi` (Spring Boot 4.1.0, Java 25, Maven)
Pipeline: GitHub Actions — `.github/workflows/maven.yml`

---

## 1. Estructura del pipeline

El pipeline se organizó en **tres etapas encadenadas** mediante `needs`, de modo que
cada una se ejecuta únicamente si la anterior finalizó correctamente:

```
1. Compilacion  →  2. Pruebas unitarias y cobertura  →  3. Empaquetado
   mvn package        mvn test + jacoco:report             mvn package
   -DskipTests        + jacoco:check (Quality Gate)        -DskipTests
```

| Etapa | Job | Comando | Qué valida |
|---|---|---|---|
| 1 | `compilacion` | `mvn -B package --file pom.xml -DskipTests` | Que el código fuente compile y empaquete |
| 2 | `pruebas` | `mvn -B test --file pom.xml`<br>`mvn -B test jacoco:report jacoco:check --file pom.xml` | Pruebas unitarias + cobertura mínima |
| 3 | `empaquetado` | `mvn -B package --file pom.xml -DskipTests` | Genera y publica el JAR ejecutable |

Si la etapa 2 falla, la etapa 3 **no se ejecuta** (aparece como *skipped* en la
interfaz de GitHub Actions). Ese es el *Quality Gate*.

### Quality Gate

Está compuesto por dos controles, ambos dentro de la etapa 2:

1. **Surefire** — si alguna prueba unitaria falla, el goal `surefire:test` retorna
   error y el job se detiene.
2. **JaCoCo `check`** — exige un mínimo de **70 % de cobertura de líneas**
   (`jacoco.line.coverage.minimum` en el `pom.xml`). Si la cobertura baja de ese
   umbral, el build falla aunque todas las pruebas pasen.

La regla de cobertura se declara a nivel de plugin (no dentro de una `<execution>`)
para que aplique en los dos modos de invocación: al llamar `jacoco:check` como goal
directo desde el pipeline, y al ejecutar `mvn verify`, donde corre enlazada a la
fase. El contador evaluado es `LINE` sobre el `BUNDLE` completo.

---

## 2. Pruebas unitarias implementadas

Se implementaron **9 pruebas** en 2 clases (`src/test/java/com/cicd/webapi/`):

| Clase | Pruebas | Qué verifica |
|---|---:|---|
| `WebapiApplicationTests` | 5 | Carga del contexto, arranque de `main()`, y que `GET /`, `GET /health` y `GET /date` respondan 200 con el contenido esperado |
| `CalculatorTest` | 4 | `add`, `subtract`, `multiply` y `divide` de la clase `Calculator`, incluida la excepción por división entre cero |

Las pruebas web usan `@SpringBootTest` junto con `@AutoConfigureMockMvc`, que
levanta el contexto completo de Spring e inyecta un `MockMvc` capaz de ejercitar
los endpoints sin abrir un puerto real. El arranque de la aplicación se verifica
con `mockStatic(SpringApplication.class)`, comprobando que `main()` delega en
`SpringApplication.run(...)`.

La clase `Calculator` incluye a propósito el método `factorial(...)` **sin prueba
asociada**, para que el reporte de cobertura muestre una zona no ejercitada y el
Quality Gate tenga algo real que medir.

> Nota técnica: en Spring Boot 4 el *slice* de pruebas de Spring MVC se separó de
> `spring-boot-starter-test` hacia su propio módulo. Por eso el `pom.xml` declara
> explícitamente la dependencia `spring-boot-webmvc-test` (scope `test`), y el
> import de la anotación cambia respecto de Spring Boot 3:
>
> ```java
> // Spring Boot 3
> import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
> // Spring Boot 4
> import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
> ```

### Ejecución local

```bash
mvn clean verify                          # compila, prueba, genera cobertura y aplica el Quality Gate
mvn test                                  # solo las pruebas
mvn test jacoco:report jacoco:check       # lo mismo que ejecuta la etapa 2 del pipeline
```

Resultado obtenido: `Tests run: 9, Failures: 0, Errors: 0, Skipped: 0`

---

## 3. Reportes publicados

El pipeline conserva los reportes como artefactos descargables desde la pestaña
**Summary** de cada ejecución:

| Artefacto | Contenido | Ruta origen | Etapa |
|---|---|---|---|
| `test-report-artifact` | XML y TXT de Surefire | `target/surefire-reports/` | 2 |
| `code-coverage-report-artifact` | Reporte HTML navegable + XML/CSV | `target/site/jacoco/` | 2 |
| `webapi-artifact` | JAR ejecutable | `target/*.jar` | 3 |

Los dos pasos de publicación de la etapa 2 usan `if: always()`, de manera que
**los reportes se suben incluso cuando las pruebas fallan** — indispensable para
diagnosticar el error. El JAR, en cambio, solo se publica si la etapa 2 pasó
completa.

### Cobertura obtenida

| Métrica | Cubierto | Total | Cobertura |
|---|---:|---:|---:|
| Instrucciones | 53 | 76 | 69.7 % |
| **Líneas** | **16** | **22** | **72.7 %** |
| Ramas | 2 | 6 | 33.3 % |
| Métodos | 13 | 14 | 92.9 % |

El Quality Gate evalúa el contador **`LINE`**, que está en 72.7 % y supera el
umbral de 70 %. Detalle por clase:

| Clase | Líneas cubiertas | Líneas perdidas | Cobertura |
|---|---:|---:|---:|
| `WebapiApplication` | 3 | 0 | 100 % |
| `HelloController` | 2 | 0 | 100 % |
| `HealthController` | 2 | 0 | 100 % |
| `DateController` | 2 | 0 | 100 % |
| `Calculator` | 7 | 6 | 53.8 % |

Las 6 líneas no cubiertas corresponden íntegramente al método `factorial(...)` de
`Calculator`, deliberadamente dejado sin prueba. El margen sobre el umbral es
estrecho (72.7 % frente a 70 %): agregar más código sin prueba haría fallar el
Quality Gate, mientras que escribir un test de `factorial` llevaría la cobertura
de líneas al 100 %.

---

## 4. Simulación de fallo (evidencia)

Para provocar el fallo del pipeline, modificar la aserción de
`checkHealthyResponse()` en
`src/test/java/com/cicd/webapi/WebapiApplicationTests.java`:

```java
// Valor correcto:
.andExpect(content().string("Server Healthy!"));

// Valor incorrecto para forzar el fallo:
.andExpect(content().string("Servidor OK"));
```

Luego `commit` y `push`. Comportamiento observado:

- **Etapa que falló:** `2. Pruebas unitarias y cobertura`, en el paso
  *Run tests with Maven*.
- **Mensaje en los registros:**

  ```
  [ERROR] Tests run: 5, Failures: 1, Errors: 0 <<< FAILURE! -- in com.cicd.webapi.WebapiApplicationTests
  java.lang.AssertionError: Response content expected:<Servidor OK> but was:<Server Healthy!>
  [ERROR] Failed to execute goal maven-surefire-plugin:test on project webapi: There are test failures.
  [INFO] BUILD FAILURE
  ```

El segundo control del Quality Gate se puede evidenciar por separado subiendo el
umbral de cobertura sin tocar ninguna prueba:

  ```
  $ mvn -B jacoco:check -Djacoco.line.coverage.minimum=0.80
  [WARNING] Rule violated for bundle webapi: lines covered ratio is 0.72, but expected minimum is 0.80
  [INFO] BUILD FAILURE
  ```

- **Cómo el pipeline evita que la compilación defectuosa continúe:** Maven
  devuelve código de salida `1`, GitHub Actions marca el job `pruebas` como
  fallido y, por la dependencia `needs: pruebas`, el job `empaquetado` queda en
  estado *skipped*. No se genera ni se publica ningún JAR.

Al revertir el cambio y volver a hacer `push`, las tres etapas vuelven a
finalizar en verde.

---

## 5. Análisis (respuestas)

**1. ¿Por qué las pruebas automatizadas son un componente esencial de la Integración Continua?**

Porque la Integración Continua no consiste solo en integrar código con
frecuencia, sino en integrarlo **con confianza**. Cada `push` introduce un riesgo
de regresión, y verificarlo manualmente no escala: sería lento, inconsistente y
dependiente de que alguien recuerde qué probar. Las pruebas automatizadas
convierten esa verificación en un proceso repetible, objetivo y ejecutado en
segundos, que además funciona como red de seguridad para refactorizar. Sin
pruebas, un pipeline de CI solo confirma que el código *compila*, lo cual no dice
nada sobre si *funciona*.

**2. ¿Qué diferencia existe entre una compilación exitosa y una validación exitosa?**

Una **compilación exitosa** significa que el código es sintácticamente válido y
que sus dependencias se resuelven: el compilador pudo producir bytecode. Es una
verificación puramente estructural. Una **validación exitosa** significa que el
programa, además de compilar, **se comporta como se espera**: los endpoints
devuelven lo correcto, las reglas de negocio se cumplen y no hay regresiones.

En este laboratorio la diferencia es literal y observable: la etapa 1
(`mvn package -DskipTests`) puede pasar perfectamente mientras la etapa 2
(`mvn test`) falla. De hecho, si se cambia `"Hello CI/CD World!"` por `"Hola"` en
el controlador, el proyecto sigue compilando y empaquetando sin un solo error,
pero la validación detecta el cambio de comportamiento. Compilar responde "¿es código válido?"; validar responde
"¿es código correcto?".

**3. ¿Qué ventajas aporta ejecutar las pruebas automáticamente después de cada cambio?**

- **Detección temprana:** el error se descubre cuando el cambio aún está fresco en
  la memoria del autor, no semanas después.
- **Costo de corrección menor:** un defecto detectado en CI cuesta órdenes de
  magnitud menos que uno detectado en producción.
- **Aislamiento de la causa:** al ejecutarse por cada commit, el conjunto de
  cambios sospechosos es pequeño y la causa raíz es evidente.
- **Trazabilidad y evidencia:** queda un registro histórico de qué se validó en
  cada versión.
- **Rama principal siempre sana:** protege el trabajo del resto del equipo, ya que
  nadie parte de una base defectuosa.
- **Eliminación del sesgo humano:** no depende de la disciplina de cada
  desarrollador para acordarse de ejecutar las pruebas.

**4. ¿Qué información proporciona el reporte de cobertura de código?**

Indica **qué porcentaje del código fue efectivamente ejecutado** durante las
pruebas, desglosado por instrucciones, líneas, ramas, métodos y clases, y permite
navegar hasta el nivel de línea individual para ver exactamente qué quedó sin
ejercitar (en JaCoCo: verde = cubierto, amarillo = parcialmente cubierto, rojo =
no cubierto). Su valor real es señalar **zonas ciegas**: en este proyecto revela
que el método `factorial(...)` de `Calculator` nunca se ejecuta en las pruebas,
pese a que el resto de la clase sí está cubierto.

Es importante entender su límite: la cobertura mide *ejecución*, no *verificación*.
Una prueba que invoca un método sin ninguna aserción aporta cobertura pero no
valida nada. Por eso una cobertura alta no garantiza calidad, aunque una cobertura
muy baja sí es una señal fiable de riesgo. Es un indicador de diagnóstico, no un
objetivo a maximizar artificialmente.

**5. ¿Qué ocurriría si un pipeline permitiera continuar el proceso a pesar de que las pruebas fallen?**

El pipeline perdería por completo su función de control de calidad y pasaría a
ser un mecanismo que **automatiza la propagación de defectos**. Consecuencias
concretas:

- Se empaquetarían y desplegarían artefactos defectuosos, llegando el error al
  usuario final.
- Los reportes de prueba se volverían "ruido": si fallar no tiene consecuencias,
  el equipo deja de mirarlos y se normaliza el rojo permanente.
- Se acumularían fallos, haciendo imposible distinguir el defecto nuevo de los
  antiguos y encareciendo cualquier corrección.
- Se perdería la confianza en el proceso, que es el activo más valioso de CI/CD.

En resumen: sin la capacidad de **detener** el flujo, un Quality Gate no es un
gate. Su poder no está en medir, sino en bloquear.

**6. ¿Qué otros tipos de pruebas podrían incorporarse en las siguientes etapas del pipeline?**

- **Pruebas de integración:** validan los componentes trabajando juntos (base de
  datos, servicios externos), típicamente con Testcontainers y `mvn failsafe`.
- **Pruebas de API / contrato:** verifican el contrato HTTP publicado
  (esquemas, códigos de estado) con REST Assured o Pact, evitando romper a los
  consumidores.
- **Pruebas End-to-End (E2E):** recorren el flujo completo desde la interfaz
  (Selenium, Playwright, Cypress).
- **Análisis estático de código (SAST):** SonarQube, SpotBugs, Checkstyle — buscan
  code smells y vulnerabilidades sin ejecutar el programa.
- **Análisis de dependencias (SCA):** OWASP Dependency-Check, Dependabot, Trivy —
  detectan CVEs conocidos en librerías de terceros.
- **Escaneo de secretos:** Gitleaks, TruffleHog — impiden que credenciales lleguen
  al repositorio.
- **Pruebas de rendimiento y carga:** JMeter, k6, Gatling — verifican latencia y
  throughput bajo carga.
- **Pruebas de seguridad dinámicas (DAST):** OWASP ZAP contra la aplicación en
  ejecución.
- **Pruebas de humo post-despliegue:** validan que el servicio recién desplegado
  responde (para eso sirve precisamente el endpoint `/health`).

El orden responde a la **pirámide de pruebas**: primero lo rápido y barato
(unitarias, análisis estático) y después lo lento y costoso (E2E, carga), de modo
que el pipeline entregue retroalimentación en el menor tiempo posible.

---

## 6. Entregables — dónde obtener cada evidencia

| Entregable | Dónde obtenerlo |
|---|---|
| URL del repositorio | `https://github.com/Integracion-y-Entrega-Continua-CI-CD/spring-boot-webapi` |
| Archivo YAML del pipeline | `.github/workflows/maven.yml` |
| Captura del pipeline exitoso | Actions → última ejecución → las 3 etapas en verde |
| Captura del pipeline fallido | Actions → ejecución del fallo inyectado → etapa 2 en rojo y etapa 3 *skipped* |
| Captura de reportes | Summary de la ejecución → sección **Artifacts** (3 artefactos) |
| Reporte de cobertura navegable | Descargar `code-coverage-report-artifact` → abrir `index.html` |
| PDF del análisis | Sección 5 de este documento |
