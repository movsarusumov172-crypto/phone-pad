using System.Net;
using System.Net.NetworkInformation;
using System.Text;
using System.Text.Json;
using PhonePad.Core;

namespace PhonePad.Server;

public static class Program
{
    public static async Task<int> Main(string[] args)
    {
        // Без этого русский текст в логах Windows превращается в «кракозябры»,
        // а перенаправленный вывод сохраняется в нечитаемой кодировке.
        Console.OutputEncoding = Encoding.UTF8;

        if (args.Any(a => a.Equals("--help", StringComparison.OrdinalIgnoreCase) ||
                          a.Equals("-h", StringComparison.OrdinalIgnoreCase)))
        {
            PrintUsage();
            return 0;
        }

        var options = LoadOptions(args);

        Console.WriteLine();
        Console.WriteLine("=== PhonePad Server — телефон как контроллер для PC ===");
        Console.WriteLine();

        IVirtualPad pad;
        string backend = (GetArg(args, "--backend") ?? "auto").ToLowerInvariant();

        if (backend == "console")
        {
            pad = new ConsolePad();
        }
        else
        {
            try
            {
                pad = CreateVigemPad();
            }
            catch (Exception ex)
            {
                Console.WriteLine($"  [!] Не удалось создать виртуальный Xbox-контроллер: {ex.GetType().Name}: {ex.Message}");
                Console.WriteLine();
                Console.WriteLine("      Варианты:");
                Console.WriteLine("      1) Установите драйвер ViGEmBus 1.22.0 (официальный установщик Nefarius):");
                Console.WriteLine("         https://github.com/nefarius/ViGEmBus/releases/tag/v1.22.0");
                Console.WriteLine("      2) Перезапустите ПК после установки драйвера.");
                Console.WriteLine("      3) Либо запустите в режиме без драйвера: PhonePadServer.exe --backend console");
                Console.WriteLine("         (ввод работает, но игра не увидит контроллер).");
                Console.WriteLine();

                if (backend == "vigem")
                {
                    return 2;
                }

                pad = new ConsolePad();
            }
        }

        Console.WriteLine($"  виртуальный контроллер: {pad.Description}");
        Console.WriteLine();

        await using var server = new PhoneServer(pad, options);
        using var cts = new CancellationTokenSource();

        Console.CancelKeyPress += (_, e) =>
        {
            e.Cancel = true;
            cts.Cancel();
        };

        PrintLocalAddresses(options.InputPort);

        try
        {
            await server.RunAsync(cts.Token).ConfigureAwait(false);
        }
        catch (OperationCanceledException)
        {
            // штатное завершение
        }

        Console.WriteLine();
        Console.WriteLine("  Сервер остановлен.");
        return 0;
    }

    private static IVirtualPad CreateVigemPad()
    {
        if (!OperatingSystem.IsWindows())
        {
            throw new PlatformNotSupportedException("ViGEmBus работает только под Windows");
        }

        // Нативная библиотека вшита в пакет Nefarius.ViGEm.Client (Costura),
        // поэтому ничего докачивать рядом с exe не нужно.
        return new VigemPad();
    }

    private static ServerOptions LoadOptions(string[] args)
    {
        var options = new ServerOptions();

        string? configPath = GetArg(args, "--config");
        string? defaultConfig = Path.Combine(AppContext.BaseDirectory, "appsettings.json");
        string? path = configPath ?? (File.Exists(defaultConfig) ? defaultConfig : null);

        if (path is not null && File.Exists(path))
        {
            try
            {
                var json = File.ReadAllText(path);
                var loaded = JsonSerializer.Deserialize<ServerOptions>(json, new JsonSerializerOptions
                {
                    PropertyNameCaseInsensitive = true
                });
                if (loaded is not null)
                {
                    options = loaded;
                }

                Console.WriteLine($"  конфиг: {path}");
            }
            catch (Exception ex)
            {
                Console.WriteLine($"  [!] Не удалось прочитать конфиг {path}: {ex.Message}");
            }
        }

        if (GetArg(args, "--port") is string p && int.TryParse(p, out int port)) options.InputPort = port;
        if (GetArg(args, "--telemetry-port") is string tp && int.TryParse(tp, out int telemetryPort)) options.TelemetryPort = telemetryPort;
        if (GetArg(args, "--feedback-port") is string fp && int.TryParse(fp, out int feedbackPort)) options.FeedbackPort = feedbackPort;
        if (GetArg(args, "--rate") is string r && int.TryParse(r, out int rate)) options.PadRateHz = rate;
        if (GetArg(args, "--timeout") is string t && int.TryParse(t, out int timeout)) options.PhoneTimeoutMs = timeout;
        if (GetArg(args, "--verbose") is not null) options.Verbose = true;

        Validate(ref options);
        return options;
    }

    /// <summary>Приводит значения к рабочим диапазонам: кривой порт уронит сокет,
    /// а слишком высокая частота отчётов съест CPU.</summary>
    private static void Validate(ref ServerOptions options)
    {
        options.InputPort = ClampPort(options.InputPort, 8888, "--port");
        options.FeedbackPort = ClampPort(options.FeedbackPort, 8889, "--feedback-port");
        options.TelemetryPort = ClampPort(options.TelemetryPort, 5300, "--telemetry-port");
        options.PadRateHz = Math.Clamp(options.PadRateHz, 20, 500);
        options.PhoneTimeoutMs = Math.Clamp(options.PhoneTimeoutMs, 50, 10_000);
    }

    private static int ClampPort(int value, int fallback, string name)
    {
        if (value is > 0 and <= 65535)
        {
            return value;
        }

        Console.WriteLine($"  [!] Некорректный порт для {name} ({value}), использую {fallback}");
        return fallback;
    }

    private static void PrintUsage()
    {
        Console.WriteLine();
        Console.WriteLine("PhonePad Server — телефон как контроллер для PC");
        Console.WriteLine();
        Console.WriteLine("  --port N              порт ввода от телефона (по умолчанию 8888)");
        Console.WriteLine("  --feedback-port N     порт обратной связи на телефоне (по умолчанию 8889)");
        Console.WriteLine("  --telemetry-port N    порт телеметрии FH6 (по умолчанию 5300)");
        Console.WriteLine("  --rate N              частота отчётов в игру, Гц (по умолчанию 100)");
        Console.WriteLine("  --timeout N           сколько мс ждать ввода до сброса пада (по умолчанию 500)");
        Console.WriteLine("  --backend vigem|console  виртуальный пад: ViGEmBus или только логи");
        Console.WriteLine("  --config PATH         свой файл конфигурации (JSON)");
        Console.WriteLine("  --verbose             подробный лог");
        Console.WriteLine("  --help                эта справка");
        Console.WriteLine();
    }

    private static string? GetArg(string[] args, string name)
    {
        for (int i = 0; i < args.Length; i++)
        {
            if (args[i].Equals(name, StringComparison.OrdinalIgnoreCase))
            {
                if (i + 1 < args.Length && !args[i + 1].StartsWith("--", StringComparison.Ordinal))
                {
                    return args[i + 1];
                }

                return "true";
            }

            if (args[i].StartsWith(name + "=", StringComparison.OrdinalIgnoreCase))
            {
                return args[i].Split('=', 2)[1];
            }
        }

        return null;
    }

    private static void PrintLocalAddresses(int port)
    {
        Console.WriteLine("  Введите в приложении на телефоне IP вашего ПК:");
        Console.WriteLine();

        try
        {
            foreach (var ni in NetworkInterface.GetAllNetworkInterfaces())
            {
                if (ni.OperationalStatus != OperationalStatus.Up || ni.NetworkInterfaceType == NetworkInterfaceType.Loopback)
                {
                    continue;
                }

                foreach (var addr in ni.GetIPProperties().UnicastAddresses)
                {
                    if (addr.Address.AddressFamily == System.Net.Sockets.AddressFamily.InterNetwork)
                    {
                        Console.WriteLine($"    {addr.Address}   ({ni.Name})");
                    }
                }
            }
        }
        catch
        {
            Console.WriteLine("    (не удалось определить адреса автоматически)");
        }

        Console.WriteLine();
        Console.WriteLine($"  В FH6: Settings → HUD and Gameplay → Data Out → ON, Data Out IP = <ваш IP>, порт 5300.");
        Console.WriteLine();
    }
}
