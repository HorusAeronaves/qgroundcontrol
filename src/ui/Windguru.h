#ifndef WINDGURU_H
#define WINDGURU_H

#include "QGCDockWidget.h"

class Windguru : public QGCDockWidget
{
    Q_OBJECT

public:
    explicit Windguru(const QString& title, QAction* action, QWidget *parent = 0);
    ~Windguru();
};

#endif // WINDGURU_H
