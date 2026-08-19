package com.cicd.webapi;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.time.LocalDate;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

/**
 * Pruebas unitarias del endpoint de fecha "/date".
 */
class DateControllerTest {

	private static final String PREFIJO = "Current Server Date: ";

	private MockMvc mockMvc;
	private DateController controller;

	@BeforeEach
	void setUp() {
		this.controller = new DateController();
		this.mockMvc = MockMvcBuilders.standaloneSetup(this.controller).build();
	}

	@Test
	@DisplayName("GET /date responde 200 OK")
	void getDateDevuelveEstado200() throws Exception {
		mockMvc.perform(get("/date"))
				.andExpect(status().isOk());
	}

	@Test
	@DisplayName("GET /date incluye la fecha actual del servidor")
	void getDateIncluyeFechaActual() throws Exception {
		String esperado = PREFIJO + LocalDate.now();

		mockMvc.perform(get("/date"))
				.andExpect(status().isOk())
				.andExpect(content().string(esperado));
	}

	@Test
	@DisplayName("La respuesta respeta el formato ISO yyyy-MM-dd")
	void respuestaUsaFormatoIso() {
		String respuesta = controller.date();

		assertThat(respuesta).startsWith(PREFIJO);
		assertThat(respuesta.substring(PREFIJO.length()))
				.matches("[0-9]{4}-[0-9]{2}-[0-9]{2}");
	}
}
