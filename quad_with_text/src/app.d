import std.stdio;
import std.container;
import std.file;
import std.path;
import std.conv;

import derelict.opengl.gl;
import derelict.sdl2.image;
import derelict.sdl2.sdl;
import derelict.sdl2.ttf;

import gapi.geometry;
import gapi.geometry_quad;
import gapi.camera;
import gapi.shader;
import gapi.shader_uniform;
import gapi.opengl;
import gapi.transform;
import gapi.texture;
import gapi.font;
import gapi.text;

import gl3n.linalg;

struct WindowData {
    SDL_Window* window;
    SDL_GLContext glContext;
    int viewportWidth = 1024;
    int viewportHeight = 768;
}

struct Geometry {
    Buffer indicesBuffer;
    Buffer verticesBuffer;
    Buffer texCoordsBuffer;

    VAO vao;
}

WindowData windowData;
Geometry sprite;
GlyphGeometry glyphGeometry;
Transform2D spriteTransform;
Transform2D glyphTransform = {
    position: vec2(32.0f, 32.0f)
};
mat4 spriteModelMatrix;
mat4 spriteMVPMatrix;
Texture2D spriteTexture;
Font dejavuFont;
Text helloWorldText;
UpdateTextResult helloWorldTextResult;
UpdateTextureTextResult helloWorldTextureTextResult;

ShaderProgram transformShader;
ShaderProgram textShader;

CameraMatrices cameraMatrices;
OthroCameraTransform cameraTransform = {
    viewportSize: vec2(1024, 768),
    position: vec2(0, 0),
    zoom: 1f
};

double currentTime = 0;
double lastTime = 0;
double frameTime = 0;

immutable partTime = 1_000.0 / 60.0;
int frames = 0;

void main() {
    DerelictGL3.load();

    DerelictSDL2.load();
    DerelictSDL2Image.load();
    DerelictSDL2TTF.load();

    run();
}

void run() {
    initSDL();
    initGL();

    onCreate();
    mainLoop();
    onDestroy();
}

void onCreate() {
    createSprite();
    createShaders();
    createTexture();
    createFont();
    createGlyphGeometry();
    createFpsText();
}

void createSprite() {
    sprite.indicesBuffer = createIndicesBuffer(quadIndices);
    sprite.verticesBuffer = createVector2fBuffer(centeredQuadVertices);
    sprite.texCoordsBuffer = createVector2fBuffer(quadTexCoords);

    sprite.vao = createVAO();

    bindVAO(sprite.vao);
    createVector2fVAO(sprite.verticesBuffer, inAttrPosition);
    createVector2fVAO(sprite.texCoordsBuffer, inAttrTextCoords);
}

void createGlyphGeometry() {
    glyphGeometry.indicesBuffer = createIndicesBuffer(quadIndices);
    glyphGeometry.verticesBuffer = createVector2fBuffer(quadVertices);
    glyphGeometry.texCoordsBuffer = createVector2fBuffer(quadTexCoords);

    glyphGeometry.vao = createVAO();

    bindVAO(glyphGeometry.vao);
    createVector2fVAO(glyphGeometry.verticesBuffer, inAttrPosition);
    createVector2fVAO(glyphGeometry.texCoordsBuffer, inAttrTextCoords);
}

void createShaders() {
    const vertexSource = readText(buildPath("res", "transform_vertex.glsl"));
    const vertexShader = createShader("transform vertex shader", ShaderType.vertex, vertexSource);

    const fragmentSource = readText(buildPath("res", "texture_fragment.glsl"));
    const fragmentShader = createShader("transform fragment shader", ShaderType.fragment, fragmentSource);

    const fragmentColorSource = readText(buildPath("res", "colorize_texatlas_fragment.glsl"));
    const fragmentColorShader = createShader("color fragment shader", ShaderType.fragment, fragmentColorSource);

    transformShader = createShaderProgram("transform program", [vertexShader, fragmentShader]);
    textShader = createShaderProgram("text program", [vertexShader, fragmentColorShader]);
}

void createTexture() {
    const Texture2DParameters params = {
        minFilter: true,
        magFilter: true
    };
    spriteTexture = createTexture2DFromFile(buildPath("res", "test.jpg"), params);
}

void createFont() {
    dejavuFont = createFontFromFile(buildPath("res", "SourceHanSerif-Regular.otf"));
}

void createFpsText() {
    helloWorldText = createText();
}

void onDestroy() {
    deleteBuffer(sprite.indicesBuffer);
    deleteBuffer(sprite.verticesBuffer);
    deleteBuffer(sprite.texCoordsBuffer);
    deleteShaderProgram(transformShader);
    deleteShaderProgram(textShader);
    deleteTexture2D(spriteTexture);
    deleteFont(dejavuFont);
    deleteText(helloWorldText);
}

void onResize(in uint width, in uint height) {
    cameraTransform.viewportSize = vec2(width, height);
    windowData.viewportWidth = width;
    windowData.viewportHeight = height;
}

void onProgress(in float deltaTime) {
    spriteTransform.position = vec2(
        cameraTransform.viewportSize.x / 2,
        cameraTransform.viewportSize.y / 2
    );
    spriteTransform.scaling = vec2(430.0f, 600.0f);
    spriteTransform.rotation += 0.25f * deltaTime;

    spriteModelMatrix = create2DModelMatrix(spriteTransform);
    cameraMatrices = createOrthoCameraMatrices(cameraTransform);
    spriteMVPMatrix = cameraMatrices.mvpMatrix * spriteModelMatrix;

    const UpdateTextInput helloWorldTextInput = {
        textSize: 32,
        font: dejavuFont,
        text: "Hello world!",
        position: glyphTransform.position,
        cameraMvpMatrix: cameraMatrices.mvpMatrix
    };
    helloWorldTextResult = updateText(helloWorldText, helloWorldTextInput);
    helloWorldTextureTextResult = updateTextureText(helloWorldText, helloWorldTextInput);
}

void onRender() {
    renderSprite();
    renderFpsText();
}

void renderSprite() {
    bindShaderProgram(transformShader);
    setShaderProgramUniformMatrix(transformShader, "MVP", spriteMVPMatrix);
    setShaderProgramUniformTexture(transformShader, "texture", spriteTexture, 0);

    bindVAO(sprite.vao);
    bindIndices(sprite.indicesBuffer);
    renderIndexedGeometry(cast(uint) quadIndices.length, GL_TRIANGLE_STRIP);
}

void renderFpsText() {
    bindShaderProgram(textShader);
    setShaderProgramUniformVec4f(textShader, "color", vec4(0, 0, 0, 1.0f));

    const RenderTextInput input = {
        shader: textShader,
        glyphGeometry: glyphGeometry,
        updateResult: helloWorldTextResult
    };
    renderText(input);

    bindShaderProgram(transformShader);
    const RenderTextureTextInput inputTextureRender = {
        shader: transformShader,
        geometry: glyphGeometry,
        updateResult: helloWorldTextureTextResult
    };
    renderTextureText(inputTextureRender);
}

void initSDL() {
    if (SDL_Init(SDL_INIT_VIDEO) < 0)
        throw new Error("Failed to init SDL");

    if (TTF_Init() < 0)
        throw new Error("Failed to init SDL TTF");

    SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 4);
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 3);
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, SDL_GL_CONTEXT_PROFILE_CORE);
    SDL_GL_SetAttribute(SDL_GL_DOUBLEBUFFER, 1);
    SDL_GL_SetAttribute(SDL_GL_MULTISAMPLESAMPLES, 16);

    SDL_GL_SetSwapInterval(2);

    windowData.window = SDL_CreateWindow(
        "Simple data oriented GAPI",
        SDL_WINDOWPOS_CENTERED,
        SDL_WINDOWPOS_CENTERED,
        windowData.viewportWidth,
        windowData.viewportHeight,
        SDL_WINDOW_OPENGL | SDL_WINDOW_RESIZABLE
    );

    if (windowData.window == null)
        throw new Error("Window could not be created! SDL Error: %s" ~ to!string(SDL_GetError()));

    windowData.glContext = SDL_GL_CreateContext(windowData.window);

    if (windowData.glContext == null)
        throw new Error("OpenGL context could not be created! SDL Error: %s" ~ to!string(SDL_GetError()));

    SDL_GL_SwapWindow(windowData.window);

    DerelictGL3.reload();
}

void initGL() {
    glDisable(GL_CULL_FACE);
    glDisable(GL_MULTISAMPLE);
    glDisable(GL_DEPTH_TEST);
    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    glClearColor(150.0f/255.0f, 150.0f/255.0f, 150.0f/255.0f, 0);

    // glDebugMessageCallback(&openglCallbackFunction, null);
}

extern(C) void openglCallbackFunction(GLenum source, GLenum type, GLuint id, GLenum severity,
                                      GLsizei length, const GLchar* message, const void* userParam)
    nothrow
    pure
{
}

void mainLoop() {
    scope(exit) SDL_GL_DeleteContext(windowData.glContext);
    scope(exit) SDL_DestroyWindow(windowData.window);
    scope(exit) SDL_Quit();
    scope(exit) TTF_Quit();

    bool running = true;

    void render() {
        if (currentTime >= lastTime + partTime) {
            const deltaTime = (currentTime - lastTime) / 1000.0f;
            onProgress(deltaTime);
            lastTime = currentTime;
            glClear(GL_COLOR_BUFFER_BIT);
            onRender();
            SDL_GL_SwapWindow(windowData.window);
            frames += 1;
        }
    }

    while (running) {
        currentTime = SDL_GetTicks();

        SDL_Event event;

        while (SDL_PollEvent(&event)) {
            if (event.type == SDL_QUIT) {
                running = false;
            }

            if (event.type == SDL_WINDOWEVENT && event.window.event == SDL_WINDOWEVENT_SIZE_CHANGED) {
                const width = event.window.data1;
                const height = event.window.data2;

                cameraTransform.viewportSize.x = width;
                cameraTransform.viewportSize.y = height;

                glViewport(0, 0, width, height);
                SDL_GL_MakeCurrent(windowData.window, windowData.glContext);
                render();
            }
        }

        render();

        if (currentTime >= frameTime + 1000.0) {
            frameTime = currentTime;
            writeln("FPS: ", frames);
            frames = 0;
        }
    }
}
