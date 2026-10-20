// Offscreen probe: verify actual qtct plugin settings, not merely rendered text.
#include <QApplication>
#include <QFontDatabase>
#include <QIcon>
#include <QJsonDocument>
#include <QJsonObject>
#include <QPalette>
#include <QProxyStyle>
#include <QStyle>
#include <QTextStream>

int main(int argc, char **argv) {
  QApplication app(argc, argv);
  const QPalette palette = app.palette();
  QStyle *baseStyle = app.style();
  while (auto *proxy = qobject_cast<QProxyStyle *>(baseStyle))
    baseStyle = proxy->baseStyle();
  QJsonObject result{
      {"qt", qVersion()},
      {"style", app.style()->objectName()},
      {"base_style", baseStyle->objectName()},
      {"font", app.font().family()},
      {"fixed_font", QFontDatabase::systemFont(QFontDatabase::FixedFont).family()},
      {"icons", QIcon::themeName()},
      {"window", palette.color(QPalette::Active, QPalette::Window).name()},
      {"foreground", palette.color(QPalette::Active, QPalette::WindowText).name()},
      {"highlight", palette.color(QPalette::Active, QPalette::Highlight).name()},
  };
  QTextStream(stdout) << QJsonDocument(result).toJson(QJsonDocument::Compact) << '\n';
  return 0;
}
