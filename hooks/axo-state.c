// Hook de BeCa para Claude Code.
//
// Recibe un identificador de estado como argumento y lo guarda en ~/.axo/state.
// El JSON que Claude Code manda por stdin se lee solo para vaciar la tubería: el
// búfer se sobrescribe y nunca se interpreta ni se guarda. Prompts, respuestas,
// rutas y comandos no salen de aquí.
//
// Nunca imprime nada, porque en SessionStart y UserPromptSubmit la salida
// estándar se agrega al contexto de Claude. Siempre termina en 0 para no
// bloquear a Claude Code. Es un binario y no un script para arrancar un solo
// proceso por evento en lugar de tres (sh, cat y mv).

#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static const char *const allowed[] = {
    "ready", "working", "reviewing", "completed", "attention", "failed", "ended",
};

static int is_allowed(const char *state) {
    for (size_t i = 0; i < sizeof(allowed) / sizeof(allowed[0]); i++) {
        if (strcmp(state, allowed[i]) == 0) return 1;
    }
    return 0;
}

int main(int argc, char **argv) {
    char discard[65536];
    while (read(STDIN_FILENO, discard, sizeof(discard)) > 0) {
    }

    if (argc != 2 || !is_allowed(argv[1])) return 0;

    char dir[1024];
    const char *custom = getenv("AXO_HOME");
    const char *home = getenv("HOME");
    if (custom && *custom) {
        snprintf(dir, sizeof(dir), "%s", custom);
    } else if (home) {
        snprintf(dir, sizeof(dir), "%s/.axo", home);
    } else {
        return 0;
    }

    char path[1100], temporary[1100];
    snprintf(path, sizeof(path), "%s/disabled", dir);
    if (access(path, F_OK) == 0) return 0;

    snprintf(temporary, sizeof(temporary), "%s/.state.%d", dir, (int)getpid());
    snprintf(path, sizeof(path), "%s/state", dir);
    int descriptor = open(temporary, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (descriptor < 0) return 0;
    size_t length = strlen(argv[1]);
    int written = write(descriptor, argv[1], length) == (ssize_t)length && write(descriptor, "\n", 1) == 1;
    close(descriptor);
    if (!written || rename(temporary, path) != 0) unlink(temporary);
    return 0;
}
