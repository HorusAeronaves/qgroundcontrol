#include "Windguru.h"
#include <QVBoxLayout>
#include <QWebEngineView>
#include <QWebEnginePage>

Windguru::Windguru(const QString& title, QAction* action, QWidget *parent)
    : QGCDockWidget(title, action, parent)
{
    QWebEngineView *view = new QWebEngineView(this);
    QVBoxLayout* lay = new QVBoxLayout();
    setLayout(lay);
    layout()->addWidget(view);
    view->setUrl(QUrl(QStringLiteral("https://www.windguru.cz/switchlang.php?lang=pt")));
    QObject::connect(view->page(),
        &QWebEnginePage::featurePermissionRequested, this,
        [=](const QUrl& /*securityOrigin*/, QWebEnginePage::Feature feature) {
            view->page()->setFeaturePermission(view->page()->url(),
                feature, QWebEnginePage::PermissionGrantedByUser);
        });
    view->show();
    adjustSize();
}


Windguru::~Windguru()
{
}
