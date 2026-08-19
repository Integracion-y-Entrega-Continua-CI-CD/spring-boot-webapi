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
 * Pruebas unitarias del endpoint raiz "/".
 */
class HelloControllerTest {

	private MockMvc mockMvc;
	private HelloController controller;

	@BeforeEach
	void setUp() {
		this.controller = new HelloController();
		this.mockMvc = MockMvcBuilders.standaloneSetup(this.controller).build();
	}

	@Test
	@DisplayName("GET / responde 200 OK")
	void getRootDevuelveEstado200() throws Exception {
		mockMvc.perform(get("/"))
				.andExpect(status().isOk());
	}

	@Test
	@DisplayName("GET / devuelve el saludo esperado")
	void getRootDevuelveSaludo() throws Exception {
		mockMvc.perform(get("/"))
				.andExpect(status().isOk())
				.andExpect(content().string("Hello, World!"));
	}

	@Test
	@DisplayName("El metodo hello() retorna el texto sin depender del contexto web")
	void helloRetornaTextoEsperado() {
		assertThat(controller.hello()).isEqualTo("Hello, World!");
	}
}
