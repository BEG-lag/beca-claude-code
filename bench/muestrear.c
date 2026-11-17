// Muestrea un proceso con proc_pid_rusage: memoria física (la columna Memoria
// del Monitor de Actividad), CPU y despertares. Uso: muestrear <pid> <segundos> <archivo.csv>
#include <libproc.h>
#include <mach/mach_time.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/proc_info.h>
#include <sys/resource.h>
#include <time.h>
#include <unistd.h>

static double now(void) {
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return t.tv_sec + t.tv_nsec / 1e9;
}

int main(int argc, char **argv) {
    if (argc != 4) return 2;
    int pid = atoi(argv[1]);
    int seconds = atoi(argv[2]);
    FILE *out = fopen(argv[3], "w");
    if (!out) return 2;
    mach_timebase_info_data_t base;
    mach_timebase_info(&base);
    fprintf(out, "t,footprint_mb,resident_mb,cpu_pct,wakeups_s,threads\n");
    struct rusage_info_v4 a, b;
    if (proc_pid_rusage(pid, RUSAGE_INFO_V4, (rusage_info_t *)&a) != 0) return 3;
    double start = now(), last = start;
    for (int i = 1; i <= seconds; i++) {
        double target = start + i;
        double wait = target - now();
        if (wait > 0) usleep((useconds_t)(wait * 1e6));
        if (proc_pid_rusage(pid, RUSAGE_INFO_V4, (rusage_info_t *)&b) != 0) return 3;
        double t = now();
        double ticks = (double)((b.ri_user_time + b.ri_system_time) - (a.ri_user_time + a.ri_system_time));
        double cpu = ticks * base.numer / base.denom / 1e9;
        double wakes = (double)((b.ri_interrupt_wkups + b.ri_pkg_idle_wkups) - (a.ri_interrupt_wkups + a.ri_pkg_idle_wkups));
        struct proc_taskinfo info;
        int threads = 0;
        if (proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, sizeof(info)) == sizeof(info)) threads = info.pti_threadnum;
        fprintf(out, "%.2f,%.3f,%.3f,%.3f,%.2f,%d\n", t - start, b.ri_phys_footprint / 1048576.0,
                b.ri_resident_size / 1048576.0, 100.0 * cpu / (t - last), wakes / (t - last), threads);
        fflush(out);
        a = b;
        last = t;
    }
    fclose(out);
    return 0;
}
