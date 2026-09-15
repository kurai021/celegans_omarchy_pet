# Experiments — C. elegans Pet

El plugin no solo es una mascota: contiene un laboratorio reproducible de
experimentos sobre su propio sistema nervioso. Cada fase vive aquí con su
harness, sus resultados y su lectura en lenguaje humano.

## Fase C — Honesty Check (qué es real del conectoma)

**Pregunta**: ¿cuánto de la navegación del pet hacia la comida emerge
realmente del connectoma, y cuánto de las capas auxiliares de `Pet.qml`
(steering Braitenberg, repulsión geométrica, ruido)?

**Por qué importa**: el proyecto afirma de entrada que el movimiento sale de
un conectoma real. Antes de añadir estímulos o modificar circuitos (fases B y
A), queremos *medir* esa afirmación y ser capaces de decir qué parte es real y
qué parte es envoltorio.

### Método

- El harness ejecuta el **`Celegans.js` real** (el mismo que `BrainConnector`),
  ciclo a ciclo, con el **mismo orden de inyección de estímulo** (tacto →
  olfato → `update()`).
- Reproduce **exactamente** el steering/física de `Pet.qml` y el olor de
  `World.qml` (sondas forward/left/right, falloff, giro gradiente Braitenberg,
  firma del conectoma `(left-right)*brainTurnGain`, giro con límite de tasa,
  reflejo de pared, nose-touch) para que lo medido coincida con la mascota
  viva.
- Entorno comparable: arena 640×480 sin rocas, 4 posiciones de pellet fijas.
  Solo el rumbo inicial y el ruido biológico son aleatorios, y ambos están
  **sembrados** (`--seed`) para que el experimento sea repetible.
- Estado del organismo congelado (hambre media = energía 50, despierto): esta
  fase mide *mecánica de navegación*, no ciclo de vida.

### Configuraciones (matriz)

| config        | chemoSideWeight | brainTurnGain | gradientGain | qué aísla |
|---------------|-----------------|---------------|--------------|-----------|
| control       | 26              | 0.05          | 300          | la mascota actual |
| aux-off       | 26              | 0.05          | 0            | rumbo solo por el conectoma |
| ct-strong-1x  | 60              | 0.5           | 0            | conectoma amplificado ×10 (sin aux) |
| ct-strong-4x  | 120             | 1.0           | 0            | conectoma amplificado ×20 (sin aux) |
| ct-off        | 26              | 0             | 300          | rumbo solo por la capa auxiliar |
| all-off       | 26              | 0             | 0            | sin control de rumbo (random-walk) |

### Reproducir

```sh
# dentro de la carpeta del plugin
node experiments/honesty-check.js                 # semilla por defecto
node experiments/honesty-check.js --seed=777      # cualquier otra semilla
node experiments/honesty-check.js --trials=80     # más repeticiones
```

Salida: tabla en consola + `experiments/results/c-<config>-<seed>.json` +
`experiments/results/honesty-matrix-<seed>.tsv`.

### Resultados (40 trials por config)

Éxito = el pet alcanzó el pellet antes del límite (2000 ciclos ≈ 200 s).

| config        | éxito (20260914) | éxito (777) | mediana ciclos→comida |
|---------------|------------------|-------------|------------------------|
| control       | 100 %            | 100 %       | 556 / 201              |
| aux-off       | 62.5 %           | 60 %        | 810 / 587              |
| ct-strong-1x  | 12.5 %           | 12.5 %      | 1460 / 985             |
| ct-strong-4x  | 0 %              | 5 %         | — / 1195               |
| ct-off        | 100 %            | 95 %        | 632 / 190              |
| all-off       | 47.5 %           | 55 %        | 789 / 1010             |

(actividad neural ≈ 30–32 neuronas/ciclo en todas las configs; magnitud de
músculos ≈ 107–114, casi simétrica `left-right ≈ –2`.)

### Lectura (honesta)

**Sí es del conectoma** (medible):
- *Locomoción*: cada paso sale de `accumleft/accumright` (músculos del cuerpo
  07–23). Ninguna capa auxiliar genera movimiento; si el connectoma no
  impulsa, el pet no se mueve.
- *Integración sensorial*: ~31 neuronas disparan por ciclo con el drive de
  food-sense de fondo.
- *Drive hacia la comida*: comida al frente → más carga en ADFL/ADFR → músculos.
- *Reflejo de tacto* en colisiones (ALML/ALMR, nose-touch).

**No es (o es envoltorio)**:
- *Eficiencia de homing* (éxito y tiempo para llegar): la lleva la capa
  auxiliar Braitenberg. Con el rumbo del conectoma anulado pero el asistente
  activo (`ct-off`), el éxito se mantiene ~95–100 % y la velocidad es la de un
  control. El random-walk puro (`all-off`) ya encuentra comida ~50 % de las
  veces en esta arena pequeña.
- *Evitación de obstáculos y reflejo de pared*: por inspección de código
  (`Pet.qml`) son repulsión geométrica / reflexión física; no pasan por el
  conectoma.

**Hallazgo**: el conectoma *solo* navega ~60 % (`aux-off`), pero **amplificar
su señal de rumbo ×10–20 colapsa el éxito al 5–13 %**. Con el mapa de
inyección actual (surplus ADFL/ADFR → músculos), más señal ≠ mejor taxis:
genera vaivén, no persecución. Esto nos dice que la afirmación "el conectoma
guía" debe decirse con matiz — la parte sensorial/integración/motora es real;
el taxis visible es sobre todo la capa auxiliar — y abre el siguiente ciclo:
**B** (mejor modelado del estímulo) y **A** (afinar el circuito).

### Archivos

- `experiments/honesty-check.js` — harness reproducible.
- `experiments/results/*.json`, `*.tsv` — resultados de cada corrida, por semilla.