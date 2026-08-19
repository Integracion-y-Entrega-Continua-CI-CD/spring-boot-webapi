#!/usr/bin/env python3
"""Genera un resumen en Markdown de las pruebas unitarias y la cobertura.

Lee los reportes que dejan Surefire (target/surefire-reports/TEST-*.xml) y
JaCoCo (target/site/jacoco/jacoco.csv) y escribe el resumen en la salida
estandar. El pipeline redirige esa salida a $GITHUB_STEP_SUMMARY para que los
resultados queden visibles en la pagina de la ejecucion.
"""

import csv
import glob
import os
import sys
import xml.etree.ElementTree as ET

SUREFIRE_XML = "target/surefire-reports/TEST-*.xml"
JACOCO_CSV = "target/site/jacoco/jacoco.csv"
UMBRAL_LINEAS = 70.0

METRICAS = (
    ("Instrucciones", "INSTRUCTION"),
    ("Lineas", "LINE"),
    ("Ramas", "BRANCH"),
    ("Metodos", "METHOD"),
    ("Clases", "CLASS"),
)


def porcentaje(cubierto, perdido):
    total = cubierto + perdido
    return None if total == 0 else 100.0 * cubierto / total


def resumen_pruebas():
    print("## Resultado de las pruebas automatizadas")
    print()

    archivos = sorted(glob.glob(SUREFIRE_XML))
    if not archivos:
        print("No se generaron reportes de pruebas: la etapa fallo antes de ejecutarlas.")
        return False

    print("| Clase de prueba | Pruebas | Fallidas | Errores | Omitidas | Tiempo (s) |")
    print("|---|---:|---:|---:|---:|---:|")

    totales = {"tests": 0, "failures": 0, "errors": 0, "skipped": 0}
    tiempo_total = 0.0

    for archivo in archivos:
        atributos = ET.parse(archivo).getroot().attrib
        for clave in totales:
            totales[clave] += int(atributos.get(clave, 0))
        tiempo_total += float(atributos.get("time", 0))
        print("| `{}` | {} | {} | {} | {} | {} |".format(
            atributos.get("name", "?"),
            atributos.get("tests", 0),
            atributos.get("failures", 0),
            atributos.get("errors", 0),
            atributos.get("skipped", 0),
            atributos.get("time", 0)))

    print("| **TOTAL** | **{}** | **{}** | **{}** | **{}** | **{:.3f}** |".format(
        totales["tests"], totales["failures"], totales["errors"],
        totales["skipped"], tiempo_total))
    print()

    exitoso = totales["failures"] == 0 and totales["errors"] == 0
    if exitoso:
        print("**Estado: PRUEBAS SUPERADAS** - {} pruebas ejecutadas sin fallos.".format(
            totales["tests"]))
    else:
        print("**Estado: PRUEBAS FALLIDAS** - {} fallidas y {} con error.".format(
            totales["failures"], totales["errors"]))
        print()
        print("Detalle de las pruebas que no pasaron:")
        print()
        for archivo in archivos:
            raiz = ET.parse(archivo).getroot()
            for caso in raiz.iter("testcase"):
                for fallo in list(caso.iter("failure")) + list(caso.iter("error")):
                    print("- `{}.{}`: {}".format(
                        caso.get("classname", "?"),
                        caso.get("name", "?"),
                        (fallo.get("message") or "sin mensaje").strip()))
    return exitoso


def resumen_cobertura():
    print()
    print("## Cobertura de codigo (JaCoCo)")
    print()

    if not os.path.exists(JACOCO_CSV):
        print("No se genero el reporte de cobertura.")
        return

    with open(JACOCO_CSV, newline="", encoding="utf-8") as handle:
        filas = list(csv.DictReader(handle))

    if not filas:
        print("El reporte de cobertura esta vacio.")
        return

    print("| Metrica | Cubierto | Total | Cobertura |")
    print("|---|---:|---:|---:|")

    cobertura_lineas = None
    for etiqueta, clave in METRICAS:
        columna_cubierto = clave + "_COVERED"
        columna_perdido = clave + "_MISSED"
        if columna_cubierto not in filas[0]:
            continue
        cubierto = sum(int(fila[columna_cubierto]) for fila in filas)
        perdido = sum(int(fila[columna_perdido]) for fila in filas)
        valor = porcentaje(cubierto, perdido)
        print("| {} | {} | {} | {} |".format(
            etiqueta, cubierto, cubierto + perdido,
            "n/a" if valor is None else "{:.1f}%".format(valor)))
        if clave == "LINE":
            cobertura_lineas = valor

    print()
    print("Umbral minimo exigido por el Quality Gate: {:.0f}% de lineas cubiertas.".format(
        UMBRAL_LINEAS))
    if cobertura_lineas is not None:
        cumple = cobertura_lineas >= UMBRAL_LINEAS
        print()
        print("**Quality Gate de cobertura: {}** ({:.1f}% de lineas).".format(
            "SUPERADO" if cumple else "NO SUPERADO", cobertura_lineas))

    print()
    print("El reporte HTML navegable se publica como artefacto "
          "`reporte-cobertura-jacoco` (abrir `index.html`).")


def main():
    resumen_pruebas()
    resumen_cobertura()
    # Siempre se sale con 0: este script solo informa. El bloqueo del pipeline
    # lo realizan Surefire y jacoco:check en la etapa de pruebas.
    return 0


if __name__ == "__main__":
    sys.exit(main())
