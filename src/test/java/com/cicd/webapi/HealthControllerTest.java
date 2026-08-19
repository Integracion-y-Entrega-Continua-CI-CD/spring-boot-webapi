package com.cicd.webapi;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

/**
 * Pruebas unitarias del endpoint de salud "/health".
 */
class HealthControllerTest {

	private MockMvc mockMvc;
	private HealthController controller;

	@BeforeEach
	void setUp() {
		this.controller = new HealthController();
		this.mockMvc = MockMvcBuilders.standaloneSetup(this.controller).build();
	}

	@Test
	@DisplayName("GET /health responde 200 OK con el mensaje de estado")
	void getHealthDevuelveEstadoSaludable() throws Exception {
		mockMvc.perform(get("/health"))
				.andExpect(status().isOk())
				.andExpect(content().string("Server Healthy!"));
	}

	@Test
	@DisplayName("El mensaje de salud nunca es vacio")
	void mensajeDeSaludNoEsVacio() {
		assertThat(controller.health()).isNotBlank();
	}
}
