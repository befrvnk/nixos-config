// Parse with the pinned Vicinae implementation; never start a launcher/server.
#include "theme/theme-file.hpp"
#include <QCoreApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QTextStream>

int main(int argc, char **argv) {
  QCoreApplication app(argc, argv);
  if (argc != 2)
    return 2;
  auto parsed = ThemeFile::fromFile(argv[1]);
  if (!parsed) {
    QTextStream(stderr) << QString::fromStdString(parsed.error()) << '\n';
    return 1;
  }
  auto &file = parsed->file;
  file.setParent(std::make_shared<ThemeFile>(
      file.isDark() ? ThemeFile::vicinaeDark() : ThemeFile::vicinaeLight()));
  QJsonArray diagnostics;
  for (const auto &diagnostic : parsed->diagnostics)
    diagnostics.append(QString::fromStdString(diagnostic));
  QJsonObject result{
      {"id", file.id()},
      {"name", file.name()},
      {"variant", file.isDark() ? "dark" : "light"},
      {"background", file.resolve(SemanticColor::Background).name()},
      {"foreground", file.resolve(SemanticColor::Foreground).name()},
      {"accent", file.resolve(SemanticColor::Accent).name()},
      {"diagnostics", diagnostics},
  };
  QTextStream(stdout) << QJsonDocument(result).toJson(QJsonDocument::Compact) << '\n';
}
