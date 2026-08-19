# Laboratorio 3 — Integración de Pruebas Automatizadas al Pipeline

Proyecto: `com.cicd:webapi` (Spring Boot 4.1.0, Java 25, Maven)
Pipeline: GitHub Actions — `.github/workflows/maven.yml`

---

## 1. Estructura del pipeline

El pipeline se organizó en **tres etapas encadenadas** mediante `needs`, de modo que
cada una se ejecuta únicamente si la anterior finalizó correctamente:

```
1. Compilacion  →  2. Pruebas unitarias y cobertura  →  3. Empaquetado
   mvn compile        mvn verify (Quality Gate)            mvn package
```

| Etapa | Job | Comando | Qué valida |
|---|---|---|---|
| 1 | `compilacion` | `mvn -B clean compile` | Que el código fuente compile |
| 2 | `pruebas` | `mvn -B verify` | Pruebas unitarias + cobertura mínima |
| 3 | `empaquetado` | `mvn -B -DskipTests package` | Genera el JAR ejecutable |

Si la etapa 2 falla, la etapa 3 **no se ejecuta** (aparece como *skipped* en la
interfaz de GitHub Actions). Ese es el *Quality Gate*.

### Quality Gate

Está compuesto por dos controles, ambos dentro de `mvn verify`:

1. **Surefire** — si alguna prueba unitaria falla, el goal `surefire:test` retorna
   error y el job se detiene.
2. **JaCoCo `check`** — exige un mínimo de **70 % de cobertura de líneas**
   (`jacoco.line.coverage.minimum` en el `pom.xml`). Si la cobertura baja de ese
   umbral, el build falla aunque todas las pruebas pasen.

---

## 2. Pruebas unitarias implementadas

Se agregaron **9 pruebas** en 4 clases (`src/test/java/com/cicd/webapi/`):

| Clase | Pruebas | Qué verifica |
|---|---:|---|
| `HelloControllerTest` | 3 | `GET /` responde 200 y devuelve `Hello, World!` |
| `HealthControllerTest` | 2 | `GET /health` responde 200 y devuelve `Server Healthy!` |
| `DateControllerTest` | 3 | `GET /date` responde 200, incluye la fecha actual y respeta el formato ISO |
| `WebapiApplicationTests` | 1 | El contexto de Spring Boot se carga correctamente |

Las pruebas de los controladores usan `MockMvcBuilders.standaloneSetup(...)`, que
levanta solo la capa web del controlador bajo prueba sin arrancar el contexto
completo de Spring. Esto las mantiene rápidas y las convierte en pruebas
unitarias reales (no de integración).

> Nota técnica: en Spring Boot 4 la anotación `@WebMvcTest` dejó de venir incluida
> en `spring-boot-starter-test`, por lo que se optó por `standaloneSetup`, que
> solo requiere `spring-test` (ya presente).

### Ejecución local

```bash
mvn clean verify        # compila, prueba, genera cobertura y aplica el Quality Gate
mvn test                # solo las pruebas
```

Resultado obtenido: `Tests run: 9, Failures: 0, Errors: 0, Skipped: 0`

---

## 3. Reportes publicados

El pipeline conserva los reportes como artefactos descargables desde la pestaña
**Summary** de cada ejecución:

| Artefacto | Contenido | Ruta origen |
|---|---|---|
| `reporte-pruebas-unitarias` | XML y TXT de Surefire | `target/surefire-reports/` |
| `reporte-cobertura-jacoco` | Reporte HTML navegable + XML/CSV | `target/site/jacoco/` |
| `aplicacion-jar` | JAR ejecutable | `target/*.jar` |

Los pasos de publicación usan `if: always()`, de manera que **los reportes se
suben incluso cuando las pruebas fallan** — indispensable para diagnosticar el
error.

Adicionalmente, el script `.github/scripts/resumen_pruebas.py` escribe en el
*Job Summary* de GitHub una tabla con el resultado de cada clase de prueba, el
detalle de las pruebas fallidas y los porcentajes de cobertura. Así el resultado
es visible sin necesidad de descargar nada.

### Cobertura obtenida

| Métrica | Cubierto | Total | Cobertura |
|---|---:|---:|---:|
| Instrucciones | 20 | 25 | 80.0 % |
| Líneas | 7 | 9 | 77.8 % |
| Métodos | 7 | 8 | 87.5 % |

Las 2 líneas no cubiertas corresponden al método `main()` de
`WebapiApplication`, que no se invoca desde las pruebas.

---

## 4. Simulación de fallo (evidencia)

Para provocar el fallo del pipeline, modificar la aserción de
`src/test/java/com/cicd/webapi/HealthControllerTest.java`:

```java
// Valor correcto:
.andExpect(content().string("Server Healthy!"));

// Valor incorrecto para forzar el fallo:
.andExpect(content().string("Servidor OK"));
```

Luego `commit` y `push`. Comportamiento observado:

- **Etapa que falló:** `2. Pruebas unitarias y cobertura`, en el paso
  *Ejecutar pruebas unitarias y validar cobertura (Quality Gate)*.
- **Mensaje en los registros:**

  ```
  [ERROR] Tests run: 2, Failures: 1, Errors: 0 <<< FAILURE! -- in com.cicd.webapi.HealthControllerTest
  java.lang.AssertionError: Response content expected:<Servidor OK> but was:<Server Healthy!>
  [ERROR] Failed to execute goal maven-surefire-plugin:test on project webapi: There are test failures.
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

En este laboratorio la diferencia es literal y observable: la etapa 1 (`mvn
compile`) puede pasar perfectamente mientras la etapa 2 (`mvn verify`) falla.
De hecho, si se cambia `"Hello, World!"` por `"Hola"` en el controlador, el
proyecto sigue compilando sin un solo error, pero la validación detecta el cambio
de comportamiento. Compilar responde "¿es código válido?"; validar responde
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
que `main()` nunca se ejecuta en las pruebas.

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
| Captura de reportes | Summary de la ejecución → tabla del resumen + sección **Artifacts** |
| Reporte de cobertura navegable | Descargar `reporte-cobertura-jacoco` → abrir `index.html` |
| PDF del análisis | Sección 5 de este documento |
